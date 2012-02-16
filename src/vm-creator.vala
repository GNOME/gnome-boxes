// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVir;

private class Boxes.VMCreator {
    private App app;
    private Connection connection { get { return app.default_connection; } }
    private VMConfigurator configurator;

    public VMCreator (App app) {
        configurator = new VMConfigurator ();
        this.app = app;

        app.collection.item_added.connect (on_item_added);
    }

    private void on_item_added (Collection collection, CollectionItem item) {
        if (!(item is LibvirtMachine))
            return;

        var machine = item as LibvirtMachine;
        if (machine.connection != connection)
            return;

        try {
            var config = machine.domain.get_config (0);
            if (!configurator.is_install_config (config) && !configurator.is_live_config (config))
                return;

            var state = machine.domain.get_info ().state;
            if (state == DomainState.SHUTOFF || state == DomainState.CRASHED || state == DomainState.NONE)
                on_domain_stopped (machine.domain);
            else
                machine.domain.stopped.connect (on_domain_stopped);
        } catch (GLib.Error error) {
            warning ("Failed to get information on domain '%s': %s", machine.domain.get_name (), error.message);
        }
    }

    public async Domain create_and_launch_vm (InstallerMedia install_media,
                                              Cancellable?   cancellable) throws GLib.Error {
        var fullscreen = true;
        if (install_media is UnattendedInstaller) {
            var unattended = install_media as UnattendedInstaller;

            yield unattended.setup (cancellable);
            fullscreen = !unattended.express_install;
        }

        var name = yield create_domain_name_from_media (install_media);
        var volume = yield create_target_volume (name, install_media.resources.storage);
        var config = configurator.create_domain_config (install_media, name, volume.get_path ());

        var domain = connection.create_domain (config);
        ulong added_signal_id = 0;
        ulong selected_signal_id = 0;
        added_signal_id = app.collection.item_added.connect ((collection, item) => {
            if (fullscreen && item is LibvirtMachine && (item as LibvirtMachine).domain == domain) {
                app.select_item (item);
                app.fullscreen = true;
                app.collection.disconnect (added_signal_id);
                app.disconnect (selected_signal_id);
            }
        });
        selected_signal_id = app.item_selected.connect (() => {
            app.collection.disconnect (added_signal_id);
            app.disconnect (selected_signal_id);
        });

        domain.start (0);

        return domain;
    }

    private void on_domain_stopped (Domain domain) {
        if (domain.get_saved ())
            // This means the domain was just saved and thefore this is not yet the time to take any post-install
            // steps for this domain.
            return;

        var volume = get_storage_volume (connection, domain);

        if (guest_installed_os (volume)) {
            post_install_setup (domain);
            domain.stopped.disconnect (on_domain_stopped);
        } else {
            try {
                var config = domain.get_config (0);

                if (!configurator.is_live_config (config))
                    return;

                // No installation during live session, so lets delete the domain and its storage volume.
                domain.stopped.disconnect (on_domain_stopped);
                domain.delete (0);
                volume.delete (0);
            } catch (GLib.Error error) {
                warning ("Failed to delete domain '%s' or its volume: %s", domain.get_name (), error.message);
            }
        }
    }

    private void post_install_setup (Domain domain) {
        try {
            var config = domain.get_config (0);
            configurator.post_install_setup (config);

            domain.set_config (config);
            domain.start (0);
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

    private async string create_domain_name_from_media (InstallerMedia install_media) throws GLib.Error {
        var base_name = (install_media.os != null) ? install_media.os.name : install_media.label;
        var name = base_name;

        var pool = yield get_storage_pool ();
        for (var i = 1; connection.find_domain_by_name (name) != null || pool.get_volume (name) != null; i++)
            name = base_name + "-" + i.to_string ();

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
