// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVirConfig;

private class Boxes.LibvirtVMImporter : Boxes.VMImporter {
    public LibvirtVMImporter (InstalledMedia source_media) {
        base (source_media);
        start_after_import = false;
    }

    public LibvirtVMImporter.for_import_completion (LibvirtMachine machine) {
        base.for_install_completion (machine);
        start_after_import = false;
    }

    protected override void create_domain_base_name_and_title (out string base_name, out string base_title) {
        var media = install_media as LibvirtMedia;

        base_name = media.domain_config.name;
        base_title = media.domain_config.title?? base_name;
    }

    protected override async Domain create_domain_config (string          name,
                                                          string          title,
                                                          string          volume_path,
                                                          Cancellable?    cancellable) throws GLib.Error {
        var media = install_media as LibvirtMedia;
        var config = media.domain_config;

        config.name = name;
        config.title = title;

        VMConfigurator.setup_custom_xml (config, install_media);
        yield VMConfigurator.update_existing_domain (config, connection);

        var devices = config.get_devices ();
        var filtered = new GLib.List<DomainDevice> ();
        var hd_index = 0;
        foreach (var device in devices) {
            if (device is DomainDisk) {
                var disk = device as DomainDisk;

                if (disk.get_source () == media.device_file)
                    /* Remove the copied over main disk configuration. */
                    continue;

                /* Let's ensure main disk configuration we're going to add, doesn't conflict with CD-ROM device. */
                if (disk.get_guest_device_type () == DomainDiskGuestDeviceType.CDROM) {
                    var dev = disk.get_target_dev ();
                    var cd_index = ((uint8) dev[dev.length - 1] - 97);

                    hd_index = (cd_index != 0)? 0 : cd_index + 1;
                }
            }

            filtered.prepend (device);
        }
        filtered.reverse ();
        config.set_devices (filtered);

        /* Add new disk configuration to match the corresponding target volume/media */
        VMConfigurator.set_target_media_config (config, volume_path, install_media, hd_index);

        return config;
    }
}
