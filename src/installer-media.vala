// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVirConfig;

private class Boxes.InstallerMedia : GLib.Object {
    public Os? os;
    public Osinfo.Resources? resources;
    public Media? os_media;
    public string label;
    public string device_file;
    public string mount_point;
    public bool from_image;

    public virtual Osinfo.DeviceList supported_devices {
        owned get {
            return (os != null)? os.get_all_devices (null) : new Osinfo.DeviceList ();
        }
    }

    public signal void user_wants_to_create (); // User wants to already create the VM

    // FIXME: Currently this information is always unknown so practically we never show any progress for installations.
    public virtual uint64 installed_size { get { return 0; } }
    public virtual bool need_user_input_for_vm_creation { get { return false; } }
    public virtual bool ready_to_create { get { return true; } }

    public bool supports_virtio_disk {
        get {
            return (find_device_by_prop (supported_devices, DEVICE_PROP_NAME, "virtio-block") != null);
        }
    }

    public bool supports_virtio_net {
        get {
            return (find_device_by_prop (supported_devices, DEVICE_PROP_NAME, "virtio-net") != null);
        }
    }

    public virtual bool live { get { return os_media == null || os_media.live; } }
    public virtual bool eject_after_install { get { return os_media == null || os_media.eject_after_install; } }

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
        yield get_device_from_path (path, cancellable);
        from_image = true;
        os_media = yield media_manager.os_db.guess_os_from_install_media_path (device_file, cancellable);
        if (os_media != null)
            os = os_media.os;

        label_setup ();

        // FIXME: these values could be made editable somehow
        var architecture = this.architecture ?? "i686";
        resources = media_manager.os_db.get_resources_for_os (os, architecture);
        resources.ram = (architecture == "i686" || architecture == "i386") ?
                        resources.ram.clamp (Osinfo.MEBIBYTES, uint32.MAX) :
                        resources.ram.clamp (Osinfo.MEBIBYTES, int64.MAX);
    }

    public virtual void set_direct_boot_params (DomainOs os) {}
    public virtual async bool prepare (ActivityProgress progress = new ActivityProgress (),
                                       Cancellable?     cancellable = null) {
        return true;
    }
    public virtual async void prepare_for_installation (string vm_name, Cancellable? cancellable) {}
    public virtual void prepare_to_continue_installation (string vm_name) {}
    public virtual void clean_up () {
        clean_up_preparation_cache ();
    }
    public virtual void clean_up_preparation_cache () {} // Clean-up any cache needed for preparing the new VM.

    public virtual void setup_domain_config (Domain domain) {
        add_cd_config (domain, from_image? DomainDiskType.FILE : DomainDiskType.BLOCK, device_file, "hdc", true);
    }

    public virtual void setup_post_install_domain_config (Domain domain) {
        eject_cdrom_media (domain);
    }

    public virtual void populate_setup_box (Gtk.Box setup_box) {}

    public virtual GLib.List<Pair<string,string>> get_vm_properties () {
        var properties = new GLib.List<Pair<string,string>> ();

        properties.append (new Pair<string,string> (_("System"), label));

        return properties;
    }

    public bool is_architecture_compatible (string architecture) {
        if (this.architecture == null)
            // Architecture unknown: let's say all architectures are compatible so caller can choose the best available
            // architecture instead. Although this is bound to fail, it's still much better than us hard coding an
            // architecture.
            return true;

        var compatibility = compare_cpu_architectures (architecture, this.architecture);

        return compatibility != CPUArchCompatibility.INCOMPATIBLE;
    }

    public virtual VMCreator get_vm_creator () {
        return new VMCreator (this);
    }

    protected void add_cd_config (Domain         domain,
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
        disk.set_target_bus (DomainDiskBus.IDE);
        if (mandatory)
            disk.set_startup_policy (DomainDiskStartupPolicy.MANDATORY);

        domain.add_device (disk);
    }

    protected void label_setup (string? label = null) {
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

    private async void get_device_from_path (string path, Cancellable? cancellable) {
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
    }

    private async void get_media_info_from_device (OSDatabase os_db) throws GLib.Error {
#if 0
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
#endif
            var media = new Osinfo.Media (device_file, ARCHITECTURE_ALL);
            media.volume_id = label;
#if 0
            get_decoded_udev_properties_for_media
                                (device,
                                 { "ID_FS_SYSTEM_ID", "ID_FS_PUBLISHER_ID", "ID_FS_APPLICATION_ID", },
                                 { MEDIA_PROP_SYSTEM_ID, MEDIA_PROP_PUBLISHER_ID, MEDIA_PROP_APPLICATION_ID },
                                 media);
#endif
            os_media = yield os_db.guess_os_from_install_media (media);
            if (os_media != null)
                os = os_media.os;
        //}
    }

#if 0
    private void get_decoded_udev_properties_for_media (GUdev.Device device,
                                                        string[]     udev_props,
                                                        string[]     media_props,
                                                        Osinfo.Media media) {
        for (var i = 0; i < udev_props.length; i++) {
            var val = get_decoded_udev_property (device, udev_props[i]);
            if (val != null)
                media.set (media_props[i], val);
        }
    }

    private string? get_decoded_udev_property (GUdev.Device device, string property_name) {
        var encoded = device.get_property (property_name);
        if (encoded == null)
            return null;

        var decoded = "";
        for (var i = 0; i < encoded.length; ) {
           uint x;

           if (encoded[i:encoded.length].scanf ("\\x%02x", out x) > 0) {
               decoded += ((char) x).to_string ();
               i += 4;
           } else {
               decoded += encoded[i].to_string ();
               i++;
           }
        }

        return decoded;
    }
#endif

    private void eject_cdrom_media (Domain domain) {
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
