// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVir;

private class Boxes.VMCreator : Object {
    // Seems installers aren't very consistent about exact number of bytes written so we ought to leave some margin
    // of error. It's better to report '100%' done while it's not exactly 100% than reporting '99%' done forever..
    private const int INSTALL_COMPLETE_PERCENT = 99;

    public InstallerMedia? install_media { get; protected set; }

    protected Connection? connection { owned get { return App.app.default_connection; } }
    private ulong state_changed_id;

    private uint num_reboots { get; private set; }

    ~VMCreator () {
        if (install_media != null)
            install_media.clean_up ();
    }

    public VMCreator (InstallerMedia install_media) {
        this.install_media = install_media;
    }

    public VMCreator.for_install_completion (LibvirtMachine machine) {
        continue_installation.begin (machine);
    }

    public async LibvirtMachine create_vm (Cancellable? cancellable, bool clone = false) throws GLib.Error {
        if (connection == null) {
            // Wait for needed libvirt connection
            ulong handler = 0;
            handler = App.app.notify["default-connection"].connect (() => {
                create_vm.callback ();
                App.app.disconnect (handler);
            });

            yield;
        }

        string title, name;
        yield create_domain_name_and_title_from_media (out name, out title);
        yield install_media.prepare_for_installation (name, cancellable);

        string? volume_path = null;
        if (install_media.skip_import && !clone) {
            volume_path = install_media.device_file;

            debug ("Skiping import. Using '%s' as target volume", volume_path);
        } else {
            var volume = yield create_target_volume (name, install_media.resources.storage);

            volume_path = volume.get_path ();
        }

        var config = yield create_domain_config (name, title, volume_path, cancellable);
        var domain = connection.create_domain (config);

        var machine = yield LibvirtBroker.get_default ().add_domain (App.app.default_source,
                                                                     App.app.default_connection,
                                                                     domain);
        machine.vm_creator = this;
        machine.run_in_bg = true;

        return machine;
    }

    public virtual void launch_vm (LibvirtMachine machine, int64 access_last_time = -1, bool clone = false) throws GLib.Error {
        state_changed_id = machine.notify["state"].connect (on_machine_state_changed);
        machine.config.access_last_time = (access_last_time > 0)? access_last_time : get_real_time ();
    }

    protected virtual async void continue_installation (LibvirtMachine machine) {
        install_media = yield MediaManager.get_default ().create_installer_media_from_config (machine.domain_config);
        num_reboots = VMConfigurator.get_num_reboots (machine.domain_config);
        var name = machine.domain.get_name ();

        if (install_media == null) {
            debug ("Could not find needed install media to continue installation, give up on automatic installation");
            set_post_install_config (machine);
            return;
        }

        install_media.prepare_to_continue_installation (name);

        state_changed_id = machine.notify["state"].connect (on_machine_state_changed);
        machine.vm_creator = this;

        on_machine_state_changed (machine);

        if (machine.state == Machine.MachineState.SAVED && VMConfigurator.is_install_config (machine.domain_config))
            try {
                yield machine.domain.start_async (0, null);
            } catch (GLib.Error e) {
                warning ("Failed to start '%s': %s", machine.name, e.message);
            }
    }

    private void on_machine_state_changed (GLib.Object object, GLib.ParamSpec? pspec = null) {
        var machine = object as LibvirtMachine;

        if (machine.is_on)
            return;

        if (machine.deleted) {
            machine.disconnect (state_changed_id);
            debug ("'%s' was deleted, no need for post-installation setup on it", machine.name);
            return;
        }

        if (machine.state == Machine.MachineState.SAVED) {
            // This means the domain was just saved and thefore this is not yet the time to take any post-install
            // steps for this domain.
            debug ("'%s' has saved state, no need for post-installation setup on it", machine.name);

            return;
        }

        if (machine.state == Machine.MachineState.FORCE_STOPPED) {
            debug ("'%s' has forced stopped, no need for post-installation setup on it", machine.name);
            return;
        }

        increment_num_reboots (machine);

        var domain = machine.domain;
        if (guest_installed_os (machine)) {
            set_post_install_config (machine);
            install_media.clean_up ();
            try {
                domain.start (0);
            } catch (GLib.Error error) {
                warning ("Failed to start domain '%s': %s", domain.get_name (), error.message);
            }
            machine.disconnect (state_changed_id);
            App.app.notify_machine_installed (machine);
            machine.vm_creator = null;
            machine.schedule_autosave ();
        } else if (!VMConfigurator.is_live_config (machine.domain_config)) {
            try {
                domain.start (0);
            } catch (GLib.Error error) {
                warning ("Failed to start domain '%s': %s", domain.get_name (), error.message);
            }
        }
    }

    protected void set_post_install_config (LibvirtMachine machine) {
        debug ("Setting post-installation configuration on '%s'", machine.name);
        try {
            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            VMConfigurator.post_install_setup (config, install_media);
            machine.domain.set_config (config);
            if (!(install_media is LibvirtClonedMedia))
                machine.run_in_bg = false;
        } catch (GLib.Error error) {
            warning ("Failed to set post-install configuration on '%s': %s", machine.name, error.message);
        }
    }

    protected virtual async GVirConfig.Domain create_domain_config (string       name,
                                                                    string       title,
                                                                    string       volume_path,
                                                                    Cancellable? cancellable) throws GLib.Error {
        var caps = yield connection.get_capabilities_async (cancellable);
        var domcaps = yield connection.get_domain_capabilities_async (null, null, null, null, 0, cancellable);
        var config = VMConfigurator.create_domain_config (install_media, volume_path, caps, domcaps);
        config.name = name;
        config.title = title;

        return config;
    }

    // Ensure name is less than 12 characters as it's also used as the hostname of the guest OS in case of
    // express installation and some OSes (you know who you are) don't like hostnames with more than 15
    // characters (we later add a '-' and a number to the name if name is not unique so we leave 3 characters
    // or that).
    protected virtual void create_domain_base_name_and_title (out string base_name, out string base_title) {
        base_title = install_media.label;
        if (install_media.os != null) {
            base_name = install_media.os.short_id;

            if (install_media.os_media != null) {
                var variants = install_media.os_media.get_os_variants ();
                if (variants.get_length () > 0)
                    // FIXME: Assuming first variant only from multivariant medias.
                    base_name += "-" + variants.get_nth (0).id;
            }

            if (base_name.length > 12)
                base_name = base_name[0:12];
        } else
            base_name = "boxes-unknown";
    }

    private void increment_num_reboots (LibvirtMachine machine) {
        num_reboots++;
        try {
            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            VMConfigurator.set_num_reboots (config, install_media, num_reboots);
            machine.domain.set_config (config);
        } catch (GLib.Error error) {
            warning ("Failed to update configuration on '%s': %s", machine.name, error.message);
        }
    }

    private bool guest_installed_os (LibvirtMachine machine) {
        var volume = machine.storage_volume;

        try {
            if (install_media.os_media != null && VMConfigurator.is_install_config (machine.domain_config))
                return (num_reboots == install_media.os_media.installer_reboots);
            else if (volume != null) {
                var info = volume.get_info ();

                // If guest has used 1 MiB of storage, we assume it installed an OS on the volume
                return (info.allocation >= Osinfo.MEBIBYTES);
            }

            return false;
        } catch (GLib.Error error) {
            warning ("Failed to get information from volume '%s': %s", volume.get_name (), error.message);
            return false;
        }
    }

    private async void create_domain_name_and_title_from_media (out string name, out string title) throws GLib.Error {
        string base_name, base_title;

        create_domain_base_name_and_title (out base_name, out base_title);

        name = base_name;
        title = base_title;
        var pool = yield Boxes.ensure_storage_pool (connection);
        for (var i = 2;
             connection.find_domain_by_name (name) != null ||
             connection.find_domain_by_name (title) != null || // We used to use title as name
             pool.get_volume (name) != null; i++) {
            // If you change the naming logic, you must address the issue of duplicate titles you'll be introducing
            name = base_name + "-" + i.to_string ();
            title = base_title + " " + i.to_string ();
        }
    }

    private async StorageVol create_target_volume (string name, int64 storage) throws GLib.Error {
        var pool = yield Boxes.ensure_storage_pool (connection);

        var config = VMConfigurator.create_volume_config (name, storage);
        debug ("Creating volume '%s'..", name);
        var volume = pool.create_volume (config);
        debug ("Created volume '%s'.", name);

        return volume;
    }
}
