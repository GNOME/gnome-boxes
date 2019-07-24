// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVirConfig;

private class Boxes.InstallerMedia : Boxes.Installer {
    
    public override bool live { get { return os_media == null || os_media.live; } }
    public override bool eject_after_install { get { return os_media == null || os_media.eject_after_install; } }

    protected virtual string? architecture {
        owned get {
            return (os_media != null)? os_media.architecture : null;
        }
    }

    public InstallerMedia.from_iso_info (string           path,
                                         string           label,
                                         Os?              os,
                                         Media?           media,
                                         Osinfo.Resources resources) {
        this.device_file = path;
        this.os = os;
        this.os_media = media;
        this.resources = resources;
        from_image = true;

        label_setup (label);
    }

    public async InstallerMedia.for_path (string       path,
                                          MediaManager media_manager,
                                          Cancellable? cancellable) throws GLib.Error {
        var device_file = yield get_device_file_from_path (path, cancellable);
#if !FLATPAK
        var device = yield get_device_from_device_file (device_file, media_manager.client);

        if (device != null)
            yield get_media_info_from_device (device, media_manager.os_db);
        else {
#endif
            from_image = true;
            os_media = yield media_manager.os_db.guess_os_from_install_media_path (device_file, cancellable);
            if (os_media != null)
                os = os_media.os;
#if !FLATPAK
        }
#endif

        label_setup ();

        // FIXME: these values could be made editable somehow
        var architecture = this.architecture ?? "i686";
        resources = media_manager.os_db.get_resources_for_os (os, architecture);
        resources.ram = (architecture == "i686" || architecture == "i386") ?
                        resources.ram.clamp (Osinfo.MEBIBYTES, uint32.MAX) :
                        resources.ram.clamp (Osinfo.MEBIBYTES, int64.MAX);
    }

    public override void setup_post_install_domain_config (Domain domain) {
        eject_cdrom_media (domain);
    }

    public override VMCreator get_vm_creator () {
        return new VMCreator (this);
    }

    protected override void add_cd_config (Domain         domain,
                                  DomainDiskType type,
                                  string?        iso_path,
                                  string         device_name,
                                  bool           mandatory = false) {
        var disk = new DomainDisk ();

        disk.set_type (type);
        disk.set_guest_device_type (DomainDiskGuestDeviceType.CDROM);
        disk.set_driver_name ("qemu");
        disk.set_driver_format (DomainDiskFormat.RAW);
        disk.set_target_dev (device_name);
        if (iso_path != null)
            disk.set_source (iso_path);
        disk.set_target_bus (prefers_q35? DomainDiskBus.SATA : DomainDiskBus.IDE);
        if (mandatory)
            disk.set_startup_policy (DomainDiskStartupPolicy.MANDATORY);

        domain.add_device (disk);
    }

    protected override void label_setup (string? label = null) {
        if (label != null)
            this.label = label;
        else if (os != null && os_media != null) {
            var variants = os_media.get_os_variants ();
            if (variants.get_length () > 0)
                // FIXME: Assuming first variant only from multivariant medias.
                this.label = (variants.get_nth (0) as OsVariant).get_name ();
            else
                this.label = os.get_name ();
        } else {
            // No appropriate label? :( Lets just use filename w/o extensions (if any) then
            var basename = get_utf8_basename (device_file);
            var ext_index = basename.index_of (".");
            this.label = (ext_index > 0)? basename[0:ext_index] : basename;

            return;
        }
    }

    public override async string get_device_file_from_path (string path, Cancellable? cancellable) {
        try {
            var mount_dir = File.new_for_path (path);
            var mount = yield mount_dir.find_enclosing_mount_async (Priority.DEFAULT, cancellable);
            var root_dir = mount.get_root ();
            if (root_dir.get_path () == mount_dir.get_path ()) {
                var volume = mount.get_volume ();
                device_file = volume.get_identifier (VolumeIdentifier.UNIX_DEVICE);
                mount_point = path;
            } else
                // Assume direct path to device node/image
                device_file = path;
        } catch (GLib.Error error) {
            // Assume direct path to device node/image
            device_file = path;
        }

        return device_file;
    }

    public override async void get_media_info_from_device (GUdev.Device device, OSDatabase os_db) throws GLib.Error {
        if (device.get_property ("ID_FS_BOOT_SYSTEM_ID") == null &&
            !device.get_property_as_boolean ("OSINFO_BOOTABLE"))
            throw new OSDatabaseError.NON_BOOTABLE ("Media %s is not bootable.", device_file);

        label = get_decoded_udev_property (device, "ID_FS_LABEL_ENC");

        var os_id = device.get_property ("OSINFO_INSTALLER") ?? device.get_property ("OSINFO_LIVE");

        if (os_id != null) {
            // Old udev and libosinfo
            os = yield os_db.get_os_by_id (os_id);

            var media_id = device.get_property ("OSINFO_MEDIA");
            if (media_id != null)
                os_media = os_db.get_media_by_id (os, media_id);
        } else {
            var media = new Osinfo.Media (device_file, ARCHITECTURE_ALL);
            media.volume_id = label;

            get_decoded_udev_properties_for_media
                                (device,
                                 { "ID_FS_SYSTEM_ID", "ID_FS_PUBLISHER_ID", "ID_FS_APPLICATION_ID", },
                                 { MEDIA_PROP_SYSTEM_ID, MEDIA_PROP_PUBLISHER_ID, MEDIA_PROP_APPLICATION_ID },
                                 media);

            os_media = yield os_db.guess_os_from_install_media (media);
            if (os_media != null)
                os = os_media.os;
        }
    }

    public override void get_decoded_udev_properties_for_media (GUdev.Device device,
                                                        string[]     udev_props,
                                                        string[]     media_props,
                                                        Osinfo.Media media) {
        for (var i = 0; i < udev_props.length; i++) {
            var val = get_decoded_udev_property (device, udev_props[i]);
            if (val != null)
                media.set (media_props[i], val);
        }
    }


    public override void eject_cdrom_media (Domain domain) {
        var devices = domain.get_devices ();
        foreach (var device in devices) {
            if (!(device is DomainDisk))
                continue;

            var disk = device as DomainDisk;
            var disk_type = disk.get_guest_device_type ();
            if (disk_type == DomainDiskGuestDeviceType.CDROM) {
                // Make source (installer/live media) optional
                disk.set_startup_policy (DomainDiskStartupPolicy.OPTIONAL);
                if (eject_after_install && !live) {
                    // eject CDROM contain in the CD drive as it will not be useful after installation
                    disk.set_source ("");
                }
            }
        }
        domain.set_devices (devices);
    }

}
