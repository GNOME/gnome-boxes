// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVir;

private class Boxes.VMCreator {
    // Seems installers aren't very consistent about exact number of bytes written so we ought to leave some margin
    // of error. Its better to report '100%' done while its not exactly 100% than reporting '99%' done forever..
    private const int INSTALL_COMPLETE_PERCENT = 99;

    public InstallerMedia? install_media { get; private set; }

    private Connection? connection { owned get { return App.app.default_connection; } }
    private ulong state_changed_id;

    private uint num_reboots { get; private set; }

    public VMCreator (InstallerMedia install_media) {
        this.install_media = install_media;
    }

    public VMCreator.for_install_completion (LibvirtMachine machine) {
        continue_installation.begin (machine);
    }

    public async LibvirtMachine create_vm (Cancellable? cancellable) throws GLib.Error {
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
        try {
            yield install_media.prepare_for_installation (name, cancellable);
        } catch (GLib.Error error) {
            App.app.notificationbar.display_error (_("An error occurred during installation preparation. Express Install disabled."));
            debug("Disabling unattended installation: %s", error.message);
        }

        var volume = yield create_target_volume (name, install_media.resources.storage);
        var caps = yield connection.get_capabilities_async (cancellable);
        var config = VMConfigurator.create_domain_config (install_media, volume.get_path (), caps);
        config.name = name;
        config.title = title;

        var domain = connection.create_domain (config);

        return LibvirtBroker.get_default ().add_domain (App.app.default_source, App.app.default_connection, domain);
    }

    public void launch_vm (LibvirtMachine machine) throws GLib.Error {
        if (!(install_media is UnattendedInstaller) || !(install_media as UnattendedInstaller).express_install) {
            ulong signal_id = 0;

            signal_id = App.app.notify["ui-state"].connect (() => {
                if (App.app.ui_state != UIState.COLLECTION)
                    return;

                App.app.select_item (machine); // This also starts the domain for us
                App.app.disconnect (signal_id);

                return;
            });
        } else
            machine.domain.start (0);

        state_changed_id = machine.notify["state"].connect (on_machine_state_changed);
        machine.vm_creator = this;
        machine.config.access_last_time = get_real_time ();
        update_machine_info (machine);
    }

    private async void continue_installation (LibvirtMachine machine) {
        install_media = yield MediaManager.get_instance ().create_installer_media_from_config (machine.domain_config);
        num_reboots = VMConfigurator.get_num_reboots (machine.domain_config);
        var name = machine.domain.get_name ();

        if (install_media == null) {
            debug ("Could not find needed install media to continue installation, give up on automatic installation");
            set_post_install_config (machine);
            return;
        }

        if (!FileUtils.test (install_media.device_file, FileTest.EXISTS)) {
            warning ("Source installer media '%s' no longer exists. Deleting machine '%s'..",
                     install_media.device_file,
                     machine.name);
            App.app.delete_machine (machine);
            return;
        }

        install_media.prepare_to_continue_installation (name);

        state_changed_id = machine.notify["state"].connect (on_machine_state_changed);
        machine.vm_creator = this;
        update_machine_info (machine);

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

        if (machine.is_on ())
            return;

        var domain = machine.domain;

        if (machine.deleted) {
            machine.disconnect (state_changed_id);
            debug ("'%s' was deleted, no need for post-installation setup on it", machine.name);
            return;
        }

        if (machine.state == Machine.MachineState.FORCE_STOPPED)
            return;

        if (machine.state == Machine.MachineState.SAVED) {
            // This means the domain was just saved and thefore this is not yet the time to take any post-install
            // steps for this domain.
            debug ("'%s' has saved state, no need for post-installation setup on it", machine.name);

            return;
        }

        increment_num_reboots (machine);

        if (guest_installed_os (machine)) {
            set_post_install_config (machine);
            install_media.clean_up ();
            try {
                domain.start (0);
            } catch (GLib.Error error) {
                warning ("Failed to start domain '%s': %s", domain.get_name (), error.message);
            }
            machine.disconnect (state_changed_id);
            if (VMConfigurator.is_live_config (machine.domain_config) || !install_trackable ())
                machine.info = null;
            machine.vm_creator = null;
        } else {
            if (VMConfigurator.is_live_config (machine.domain_config)) {
                // No installation during live session, so lets delete the VM
                machine.disconnect (state_changed_id);
                install_media.clean_up ();
                App.app.delete_machine (machine);
            } else
                try {
                    domain.start (0);
                } catch (GLib.Error error) {
                    warning ("Failed to start domain '%s': %s", domain.get_name (), error.message);
                }
        }
    }

    private void update_machine_info (LibvirtMachine machine) {
        if (VMConfigurator.is_install_config (machine.domain_config)) {
            machine.info = _("Installing...");

            track_install_progress (machine);
        } else
            machine.info = _("Live");
    }

    private void set_post_install_config (LibvirtMachine machine) {
        debug ("Setting post-installation configuration on '%s'", machine.name);
        try {
            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            VMConfigurator.post_install_setup (config, install_media);
            machine.domain.set_config (config);
        } catch (GLib.Error error) {
            warning ("Failed to set post-install configuration on '%s': %s", machine.name, error.message);
        }
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
            if (install_trackable ())
                // Great! We know how much storage installed guest consumes
                return get_progress (volume) == INSTALL_COMPLETE_PERCENT;
            else if (install_media.os_media != null && VMConfigurator.is_install_config (machine.domain_config))
                return (num_reboots == install_media.os_media.installer_reboots);
            else {
                var info = volume.get_info ();

                // If guest has used 1 MiB of storage, we assume it installed an OS on the volume
                return (info.allocation >= Osinfo.MEBIBYTES);
            }
        } catch (GLib.Error error) {
            warning ("Failed to get information from volume '%s': %s", volume.get_name (), error.message);
            return false;
        }
    }

    int prev_progress = 0;
    bool updating_install_progress;
    private void track_install_progress (LibvirtMachine machine) {
        if (!install_trackable ())
            return;

        return_if_fail (machine.storage_volume != null);

        Timeout.add_seconds (6, () => {
            if (prev_progress == 100) {
                machine.info = null;

                return false;
            }

            if (!updating_install_progress)
                update_install_progress.begin (machine);

            return true;
        });
    }

    private async void update_install_progress (LibvirtMachine machine) {
        updating_install_progress = true;

        int progress = 0;
        try {
            yield run_in_thread (() => {
                progress = get_progress (machine.storage_volume);
            });
        } catch (GLib.Error error) {
            warning ("Failed to get information from volume '%s': %s",
                     machine.storage_volume.get_name (),
                     error.message);
        }
        if (progress < 0)
            return;

        // This string is about automatic installation progress
        machine.info = ngettext ("%d%% Installed", "%d%% Installed", progress).printf (progress);
        prev_progress = progress;
        updating_install_progress = false;
    }

    private bool install_trackable () {
        return (install_media.installed_size > 0);
    }

    private int get_progress (GVir.StorageVol volume) throws GLib.Error {
        var volume_info = volume.get_info ();

        var percent = (int) (volume_info.allocation * 100 /  install_media.installed_size);

        // Make sure we don't display some rediculous figure in case we are wrong about installed size or libvirt
        // gives us incorrect value for bytes written to disk.
        percent = percent.clamp (0, INSTALL_COMPLETE_PERCENT);

        if (percent == INSTALL_COMPLETE_PERCENT)
            percent = 100;

        return percent;
    }

    private async void create_domain_name_and_title_from_media (out string name, out string title) throws GLib.Error {
        var base_title = install_media.label;
        title = base_title;
        var base_name = (install_media.os != null) ? install_media.os.short_id : "boxes-unknown";
        name = base_name;

        var pool = yield get_storage_pool ();
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
        var pool = yield get_storage_pool ();

        var config = VMConfigurator.create_volume_config (name, storage);
        var volume = pool.create_volume (config);

        return volume;
    }

    private async StoragePool get_storage_pool () throws GLib.Error {
        var pool = Boxes.get_storage_pool (connection);
        if (pool == null) {
            var config = VMConfigurator.get_pool_config ();
            pool = connection.create_storage_pool (config, 0);
            yield pool.build_async (0, null);
            yield pool.start_async (0, null);
            yield pool.refresh_async (null);
        }

        return pool;
    }
}
