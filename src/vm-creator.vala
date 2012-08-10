// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVir;

private class Boxes.VMCreator {
    public InstallerMedia? install_media { get; private set; }

    private Connection? connection { get { return App.app.default_connection; } }
    private ulong state_changed_id;

    public VMCreator (InstallerMedia install_media) {
        this.install_media = install_media;
    }

    public VMCreator.for_install_completion (LibvirtMachine machine) {
        state_changed_id = machine.notify["state"].connect (on_machine_state_changed);
        machine.vm_creator = this;

        on_machine_state_changed (machine);
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
        yield install_media.prepare_for_installation (name, cancellable);

        var volume = yield create_target_volume (name, install_media.resources.storage);
        var caps = yield connection.get_capabilities_async (cancellable);
        var config = VMConfigurator.create_domain_config (install_media, volume.get_path (), caps);
        config.name = name;
        config.title = title;

        var domain = connection.create_domain (config);

        return App.app.add_domain (App.app.default_source, App.app.default_connection, domain);
    }

    public void launch_vm (LibvirtMachine machine) throws GLib.Error {
        if (!(install_media is UnattendedInstaller) || !(install_media as UnattendedInstaller).express_install) {
            ulong signal_id = 0;

            signal_id = App.app.notify["ui-state"].connect (() => {
                if (App.app.ui_state != UIState.COLLECTION)
                    return;

                App.app.select_item (machine); // This also starts the domain for us
                App.app.fullscreen = true;
                App.app.disconnect (signal_id);

                return;
            });
        } else
            machine.domain.start (0);

        set_post_install_config (machine);

        state_changed_id = machine.notify["state"].connect (on_machine_state_changed);
        machine.vm_creator = this;
    }

    private void on_machine_state_changed (GLib.Object object, GLib.ParamSpec? pspec = null) {
        var machine = object as LibvirtMachine;

        if (machine.state != Machine.MachineState.STOPPED && machine.state != Machine.MachineState.UNKNOWN)
            return;

        var domain = machine.domain;

        if (machine.deleted) {
            machine.disconnect (state_changed_id);
            debug ("'%s' was deleted, no need for post-installation setup on it", machine.name);
            return;
        }

        if (domain.get_saved ()) {
            debug ("'%s' has saved state, no need for post-installation setup on it", machine.name);
            // This means the domain was just saved and thefore this is not yet the time to take any post-install
            // steps for this domain.
            if (VMConfigurator.is_install_config (machine.domain_config))
                domain.start_async.begin (0, null);

            return;
        }

        var volume = get_storage_volume (connection, domain, null);

        if (guest_installed_os (volume)) {
            mark_as_installed (machine);
            try {
                domain.start (0);
            } catch (GLib.Error error) {
                warning ("Failed to start domain '%s': %s", domain.get_name (), error.message);
            }
            machine.disconnect (state_changed_id);
            machine.vm_creator = null;
        } else {
            if (!VMConfigurator.is_live_config (machine.domain_config))
                return;

            // No installation during live session, so lets delete the VM
            machine.disconnect (state_changed_id);
            App.app.delete_machine (machine);
        }
    }

    private void set_post_install_config (LibvirtMachine machine) {
        debug ("Setting post-installation configuration on '%s'", machine.name);
        try {
            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            VMConfigurator.post_install_setup (config);
            machine.domain.set_config (config);
        } catch (GLib.Error error) {
            warning ("Failed to set post-install configuration on '%s' failed: %s", machine.name, error.message);
        }
    }

    private void mark_as_installed (LibvirtMachine machine) requires (machine.state == Machine.MachineState.STOPPED ||
                                                                      machine.state == Machine.MachineState.UNKNOWN) {
        debug ("Marking '%s' as installed.", machine.name);
        try {
            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            VMConfigurator.mark_as_installed (config);
            machine.domain.set_config (config);
        } catch (GLib.Error error) {
            warning ("Failed to marking domain '%s' as installed: %s", machine.name, error.message);
        }
    }

    private bool guest_installed_os (StorageVol volume) {
        try {
            var info = volume.get_info ();

            // If guest has used 1 MiB of storage, we assume it installed an OS on the volume
            return (info.allocation >= Osinfo.MEBIBYTES);
        } catch (GLib.Error error) {
            warning ("Failed to get information from volume '%s': %s", volume.get_name (), error.message);
            return false;
        }
    }

    private async void create_domain_name_and_title_from_media (out string name, out string title) throws GLib.Error {
        var base_title = install_media.label;
        title = base_title;
        var base_name = (install_media.os != null) ? install_media.os.short_id : base_title;
        if (install_media.live)
            base_name += "-live";
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
        var pool = connection.find_storage_pool_by_name (Config.PACKAGE_TARNAME);
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
