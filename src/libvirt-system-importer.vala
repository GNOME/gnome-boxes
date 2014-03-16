// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;

errordomain Boxes.LibvirtSystemImporterError {
    NO_IMPORTS,
    NO_SUITABLE_DISK
}

private class Boxes.LibvirtSystemImporter: GLib.Object {
    private GVir.Connection connection;
    private GLib.List<GVir.Domain> domains;

    public string wizard_menu_label {
        owned get {
            var num_domains = domains.length ();

            if (num_domains == 1)
                return _("Import '%s' from system broker").printf (domains.data.get_name ());
            else
                // Translators: %u here is the number of boxes available for import
                return ngettext ("Import %u box from system broker",
                                 "Import %u boxes from system broker",
                                 num_domains).printf (num_domains);
        }
    }

    public string wizard_review_label {
        owned get {
            var num_domains = domains.length ();

            if (num_domains == 1)
                return _("Will import '%s' from system broker").printf (domains.data.get_name ());
            else
                // Translators: %u here is the number of boxes available for import
                return ngettext ("Will import %u box from system broker",
                                 "Will import %u boxes from system broker",
                                 num_domains).printf (num_domains);
        }
    }

    public async LibvirtSystemImporter () throws LibvirtSystemImporterError.NO_IMPORTS {
        connection = new GVir.Connection ("qemu+unix:///system");

        try {
            yield connection.open_read_only_async (null);
            debug ("Connected to system libvirt, now fetching domains..");
            yield connection.fetch_domains_async (null);
        } catch (GLib.Error error) {
            warning ("Failed to connect to system libvirt: %s", error.message);

            return;
        }

        domains = connection.get_domains ();
        debug ("Fetched %u domains from system libvirt.", domains.length ());
        if (domains.length () == 0)
            throw new LibvirtSystemImporterError.NO_IMPORTS (_("No boxes to import"));
    }

    public async void import () {
        GVirConfig.Domain[] configs = {};
        string[] disk_paths = {};

        foreach (var domain in domains) {
            GVirConfig.Domain config;
            string disk_path;

            try {
                get_domain_info (domain, out config, out disk_path);
                configs += config;
                disk_paths += disk_path;
            } catch (GLib.Error error) {
                warning ("%s", error.message);
            }
        }

        try {
            yield ensure_disks_readable (disk_paths);
        } catch (GLib.Error error) {
            warning ("Failed to make all libvirt system disks readable: %s", error.message);

            return;
        }

        for (var i = 0; i < configs.length; i++)
            import_domain.begin (configs[i], disk_paths[i], null, (obj, result) => {
                try {
                    import_domain.end (result);
                } catch (GLib.Error error) {
                    warning ("Failed to import '%s': %s", configs[i].name, error.message);
                }
            });
    }

    private void get_domain_info (Domain domain, out GVirConfig.Domain config, out string disk_path) throws GLib.Error {
        debug ("Fetching config for '%s' from system libvirt.", domain.get_name ());
        config = domain.get_config (DomainXMLFlags.INACTIVE);
        debug ("Finding a suitable disk to import for '%s' from system libvirt.", domain.get_name ());
        disk_path = get_disk_path (config);
    }

    private async void import_domain (GVirConfig.Domain config,
                                      string            disk_path,
                                      Cancellable?      cancellable = null) throws GLib.Error {
        debug ("Importing '%s' from system libvirt..", config.name);

        var media = new LibvirtSystemMedia (disk_path, config);
        var vm_importer = media.get_vm_creator ();
        var machine = yield vm_importer.create_vm (cancellable);
        vm_importer.launch_vm (machine);
    }

    private string get_disk_path (GVirConfig.Domain config) throws LibvirtSystemImporterError.NO_SUITABLE_DISK {
        string disk_path = null;

        var devices = config.get_devices ();
        foreach (var device in devices) {
            if (!(device is GVirConfig.DomainDisk))
                continue;

            var disk = device as GVirConfig.DomainDisk;
            if (disk.get_guest_device_type () == GVirConfig.DomainDiskGuestDeviceType.DISK) {
                disk_path = disk.get_source ();

                break;
            }
        }

        if (disk_path == null)
            throw new LibvirtSystemImporterError.NO_SUITABLE_DISK
                                    (_("Failed to find suitable disk to import for box '%s'"), config.name);

        return disk_path;
    }

    private async void ensure_disks_readable (string[] disk_paths) throws GLib.Error {
        string[] argv = {};

        argv += "pkexec";
        argv += "chmod";
        argv += "a+r";
        foreach (var disk_path in disk_paths)
            argv += disk_path;

        debug ("Making all libvirt system disks readable..");
        yield exec (argv, null);
        debug ("Made all libvirt system disks readable.");
    }
}
