// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVirConfig;

private class Boxes.LibvirtSystemVMImporter : Boxes.VMImporter {
    public LibvirtSystemVMImporter (InstalledMedia source_media) {
        base (source_media);
        start_after_import = false;
    }

    public LibvirtSystemVMImporter.for_import_completion (LibvirtMachine machine) {
        base.for_install_completion (machine);
        start_after_import = false;
    }

    protected override void create_domain_base_name_and_title (out string base_name, out string base_title) {
        var media = install_media as LibvirtSystemMedia;

        base_name = media.domain_config.name;
        base_title = media.domain_config.title?? base_name;
    }

    protected override async Domain create_domain_config (string          name,
                                                          string          title,
                                                          GVir.StorageVol volume,
                                                          Cancellable?    cancellable) throws GLib.Error {
        var media = install_media as LibvirtSystemMedia;
        var config = media.domain_config;

        config.name = name;
        config.title = title;

        VMConfigurator.setup_custom_xml (config, install_media);

        var devices = config.get_devices ();
        foreach (var device in devices) {
            if (!(device is DomainDisk))
                continue;

            var disk = device as DomainDisk;
            if (disk.get_source () == media.device_file) {
                disk.set_source (volume.get_path ());

                break;
            }
        }
        config.set_devices (devices);

        return config;
    }
}
