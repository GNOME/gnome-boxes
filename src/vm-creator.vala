// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVir;

private class Boxes.VMCreator {
    private Connection connection;
    private VMConfigurator configurator;

    public VMCreator (App app) throws GLib.Error {
        connection = app.default_connection;
        configurator = new VMConfigurator ();
    }

    public async Domain create_and_launch_vm (InstallerMedia install_media,
                                              Resources      resources,
                                              Cancellable?   cancellable) throws GLib.Error {
        if (install_media is UnattendedInstaller)
            yield (install_media as UnattendedInstaller).setup (cancellable);

        string name;
        if (install_media.os != null)
            name = install_media.os.name;
        else
            name = install_media.label;

        var domain_name = name;
        for (var i = 1; connection.find_domain_by_name (domain_name) != null; i++)
            domain_name = name + "-" + i.to_string ();

        var volume = yield create_target_volume (name, resources.storage);
        var config = configurator.create_domain_config (install_media, domain_name, volume.get_path (), resources);

        Domain domain;
        if (install_media.live)
            // We create a (initially) transient domain for live and unknown media
            domain = connection.start_domain (config, 0);
        else {
            domain = connection.create_domain (config);
            domain.start (0);
            config = domain.get_config (0);
        }

        ulong id = 0;
        id = domain.stopped.connect (() => {
            if (guest_installed_os (volume)) {
                post_install_setup (domain, config, !install_media.live);
                domain.disconnect (id);
            } else if (install_media.live) {
                domain.disconnect (id);
                // Domain is gone then so we should delete associated storage volume.
                try {
                    volume.delete (0);
                } catch (GLib.Error error) {
                    warning ("Failed to delete volume '%s': %s", volume.get_path (), error.message);
                }
            }
        });

        return domain;
    }

    private void post_install_setup (Domain domain, GVirConfig.Domain config, bool permanent) {
        configurator.post_install_setup (config);

        try {
            if (permanent) {
                domain.set_config (config);
                domain.start (0);
            } else {
                var new_domain = connection.create_domain (config);
                new_domain.start (0);
            }
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

    private async StorageVol create_target_volume (string name, int64 storage) throws GLib.Error {
        var pool = yield get_storage_pool ();

        var volume_name = name + ".qcow2";
        for (var i = 1; pool.get_volume (volume_name) != null; i++)
            volume_name = name + "-" + i.to_string () + ".qcow2";

        var config = configurator.create_volume_config (volume_name, storage);
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
        }

        // This should be async
        pool.refresh (null);

        return pool;
    }
}
