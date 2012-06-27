// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVir;

private class Boxes.VMCreator {
    private Connection? connection { get { return App.app.default_connection; } }
    private VMConfigurator configurator;
    private ulong stopped_id;

    public VMCreator () {
        configurator = new VMConfigurator ();

        App.app.collection.item_added.connect (on_item_added);
    }

    private void on_item_added (Collection collection, CollectionItem item) {
        if (!(item is LibvirtMachine))
            return;

        var machine = item as LibvirtMachine;
        if (machine.connection != connection)
            return;

        try {
            var config = machine.domain.get_config (0);
            if (!configurator.is_install_config (config) && !configurator.is_live_config (config)) {
                debug ("'%s' does not need post-installation setup", machine.name);
                return;
            }

            var state = machine.domain.get_info ().state;
            if (state == DomainState.SHUTOFF || state == DomainState.CRASHED || state == DomainState.NONE)
                on_domain_stopped (machine);
            else {
                stopped_id = machine.domain.stopped.connect (() => { on_domain_stopped (machine); });
            }
        } catch (GLib.Error error) {
            warning ("Failed to get information on domain '%s': %s", machine.domain.get_name (), error.message);
        }
    }

    public async LibvirtMachine create_vm (InstallerMedia install_media, Cancellable? cancellable) throws GLib.Error {
        if (connection == null) {
            // Wait for needed libvirt connection
            ulong handler = 0;
            handler = App.app.notify["default-connection"].connect (() => {
                create_vm.callback ();
                App.app.disconnect (handler);
            });

            yield;
        }

        string title;
        var name = yield create_domain_name_and_title_from_media (install_media, out title);
        if (install_media is UnattendedInstaller)
            yield (install_media as UnattendedInstaller).setup (name, cancellable);

        var volume = yield create_target_volume (name, install_media.resources.storage);
        var caps = yield connection.get_capabilities_async (cancellable);
        var config = configurator.create_domain_config (install_media, volume.get_path (), caps);
        config.name = name;
        config.title = title;

        var domain = connection.create_domain (config);

        return App.app.add_domain (App.app.default_source, App.app.default_connection, domain);
    }

    public void launch_vm (LibvirtMachine machine, InstallerMedia install_media) throws GLib.Error {
        machine.domain.start (0);

        post_install_setup (machine.domain);

        if (!(install_media is UnattendedInstaller) || !(install_media as UnattendedInstaller).express_install) {
            ulong signal_id = 0;

            signal_id = App.app.notify["ui-state"].connect (() => {
                if (App.app.ui_state != UIState.COLLECTION)
                    return;

                App.app.select_item (machine);
                App.app.fullscreen = true;
                App.app.disconnect (signal_id);

                return;
            });
        }
    }

    private void on_domain_stopped (LibvirtMachine machine) {
        var domain = machine.domain;

        if (machine.deleted) {
            debug ("'%s' was deleted, no need for post-installation setup on it", machine.name);
            return;
        }

        if (domain.get_saved ()) {
            debug ("'%s' has saved state, no need for post-installation setup on it", machine.name);
            // This means the domain was just saved and thefore this is not yet the time to take any post-install
            // steps for this domain.
            return;
        }

        var volume = get_storage_volume (connection, domain, null);

        if (guest_installed_os (volume)) {
            try {
                domain.start (0);
            } catch (GLib.Error error) {
                warning ("Failed to start domain '%s': %s", domain.get_name (), error.message);
            }
            domain.disconnect (stopped_id);
        } else {
            try {
                var config = domain.get_config (0);

                if (!configurator.is_live_config (config))
                    return;

                // No installation during live session, so lets delete the VM
                domain.disconnect (stopped_id);
                App.app.delete_machine (machine);
            } catch (GLib.Error error) {
                warning ("Failed to delete domain '%s' or its volume: %s", domain.get_name (), error.message);
            }
        }
    }

    private void post_install_setup (Domain domain) {
        debug ("Performing post-installation setup on '%s'", domain.get_name ());
        try {
            var config = domain.get_config (0);
            configurator.post_install_setup (config);
            domain.set_config (config);
        } catch (GLib.Error error) {
            warning ("Post-install setup failed for domain '%s': %s", domain.get_uuid (), error.message);
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

    private async string create_domain_name_and_title_from_media (InstallerMedia install_media,
                                                                  out string     title) throws GLib.Error {
        var base_title = install_media.label;
        title = base_title;
        var base_name = (install_media.os != null) ? install_media.os.short_id : base_title;
        var name = base_name;

        var pool = yield get_storage_pool ();
        for (var i = 2;
             connection.find_domain_by_name (name) != null ||
             connection.find_domain_by_name (title) != null || // We used to use title as name
             pool.get_volume (name) != null; i++) {
            // If you change the naming logic, you must address the issue of duplicate titles you'll be introducing
            name = base_name + "-" + i.to_string ();
            title = base_title + " " + i.to_string ();
        }

        return name;
    }

    private async StorageVol create_target_volume (string name, int64 storage) throws GLib.Error {
        var pool = yield get_storage_pool ();

        var config = configurator.create_volume_config (name, storage);
        var volume = pool.create_volume (config);

        return volume;
    }

    private async StoragePool get_storage_pool () throws GLib.Error {
        var pool = connection.find_storage_pool_by_name (Config.PACKAGE_TARNAME);
        if (pool == null) {
            var config = configurator.get_pool_config ();
            pool = connection.create_storage_pool (config, 0);
            yield pool.build_async (0, null);
            yield pool.start_async (0, null);
            yield pool.refresh_async (null);
        }

        return pool;
    }
}
