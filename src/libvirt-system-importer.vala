// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;

errordomain Boxes.LibvirtSystemImporterError {
    NO_IMPORTS,
    NO_SUITABLE_DISK
}

private class Boxes.LibvirtSystemImporter: GLib.Object {
    private GVir.Connection connection;

    private GLib.List<GVir.Domain> domains;
    private string[] disk_paths;
    private GVirConfig.Domain[] configs;

    public string wizard_menu_label {
        owned get {
            var num_domains = domains.length ();

            if (num_domains == 1)
                return _("_Import '%s' from system broker").printf (domains.data.get_name ());
            else
                // Translators: %u here is the number of boxes available for import
                return ngettext ("_Import %u box from system broker",
                                 "_Import %u boxes from system broker",
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

    public async LibvirtSystemImporter () throws GLib.Error {
        connection = yield get_system_virt_connection ();

        var domains = system_virt_connection.get_domains ();

        foreach (var domain in domains) {
            try {
                string disk_path;
                var config = new GVirConfig.Domain ();

                get_domain_info (domain, out config, out disk_path);

                var file = File.new_for_path (disk_path);
                if (file.query_exists ()) {
                    this.domains.append (domain);
                    disk_paths += disk_path;
                    configs += config;
                } else {
                    debug ("Could not find a valid disk image for %s", domain.get_name ());
                }
            } catch (GLib.Error error) {
                warning ("%s", error.message);
            }
        }

        debug ("Fetched %u domains from system libvirt.", this.domains.length ());
        if (this.domains.length () == 0)
            throw new LibvirtSystemImporterError.NO_IMPORTS (_("No boxes to import"));
    }

    public async void import () {
        try {
            yield ensure_disks_readable (disk_paths);
        } catch (GLib.Error error) {
            warning ("Failed to make all libvirt system disks readable: %s", error.message);

            return;
        }

        for (var i = 0; i < configs.length; i++)
            import_domain.begin (configs[i], disk_paths[i], null);
    }

    private void get_domain_info (Domain domain,
                                  out GVirConfig.Domain config,
                                  out string disk_path) throws GLib.Error {
        debug ("Fetching config for '%s' from system libvirt.", domain.get_name ());
        config = domain.get_config (DomainXMLFlags.INACTIVE);
        debug ("Finding a suitable disk to import for '%s' from system libvirt.", domain.get_name ());
        disk_path = get_disk_path (config);
    }

    private async void import_domain (GVirConfig.Domain config,
                                      string            disk_path,
                                      Cancellable?      cancellable = null) {
        debug ("Importing '%s' from system libvirt..", config.name);

        try {
            var media = new LibvirtSystemMedia (disk_path, config);
            var vm_importer = media.get_vm_creator ();
            var machine = yield vm_importer.create_vm (cancellable);
            vm_importer.launch_vm (machine);
        } catch (GLib.Error error) {
            warning ("Failed to import '%s': %s", config.name, error.message);
        }
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

        foreach (var disk_path in disk_paths) {
            var file = File.new_for_path (disk_path);
            var info = yield file.query_info_async (FileAttribute.ACCESS_CAN_READ,
                                                    FileQueryInfoFlags.NONE,
                                                    Priority.DEFAULT,
                                                    null);
            if (!info.get_attribute_boolean (FileAttribute.ACCESS_CAN_READ)) {
                debug ("'%s' not readable, gotta make it readable..", disk_path);
                argv += disk_path;
            }
        }

        if (argv.length == 3)
            return;

        debug ("Making all libvirt system disks readable..");
        yield exec (argv, null);
        debug ("Made all libvirt system disks readable.");
    }
}
