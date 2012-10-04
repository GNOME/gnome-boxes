// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GUdev;
using GVirConfig;

private class Boxes.InstallerMedia : GLib.Object {
    public Os? os;
    public Osinfo.Resources? resources;
    public Media? os_media;
    public string label;
    public string device_file;
    public string mount_point;
    public bool from_image;

    // FIXME: Currently this information is always unknown so practically we never show any progress for installations.
    public virtual uint64 installed_size { get { return 0; } }
    public virtual bool need_user_input_for_vm_creation { get { return false; } }
    public virtual bool user_data_for_vm_creation_available { get { return true; } }
    public virtual bool supports_virtio_disk {
        get {
            return (get_os_device_by_prop (os, DEVICE_PROP_NAME, "virtio-block") != null);
        }
    }

    public bool live { get { return os_media == null || os_media.live; } }

    public InstallerMedia.from_iso_info (string           path,
                                         string           label,
                                         Os               os,
                                         Media            media,
                                         Osinfo.Resources resources) {
        this.device_file = path;
        this.os = os;
        this.os_media = media;
        this.resources = resources;
        from_image = true;

        setup_label (label);
    }

    public static async InstallerMedia create_for_path (string       path,
                                                        MediaManager media_manager,
                                                        Cancellable? cancellable) throws GLib.Error {
        var media = new InstallerMedia ();

        yield media.setup_for_path (path, media_manager, cancellable);

        return media;
    }

    private async void setup_for_path (string       path,
                                       MediaManager media_manager,
                                       Cancellable? cancellable) throws GLib.Error {
        var device = yield get_device_from_path (path, media_manager.client, cancellable);

        if (device != null)
            get_media_info_from_device (device, media_manager.os_db);
        else {
            from_image = true;
            os = yield media_manager.os_db.guess_os_from_install_media (device_file, out os_media, cancellable);
        }

        setup_label ();

        // FIXME: these values could be made editable somehow
        var architecture = (os_media != null) ? os_media.architecture : "i686";
        resources = media_manager.os_db.get_resources_for_os (os, architecture);
    }

    public virtual void set_direct_boot_params (DomainOs os) {}
    public virtual async void prepare_for_installation (string vm_name, Cancellable? cancellable) throws GLib.Error {}

    public virtual void setup_domain_config (Domain domain) {
        add_cd_config (domain, from_image?DomainDiskType.FILE:DomainDiskType.BLOCK, device_file, "hdc", true);
    }

    public virtual void populate_setup_vbox (Gtk.VBox setup_vbox) {}

    public virtual GLib.List<Pair<string,string>> get_vm_properties () {
        var properties = new GLib.List<Pair<string,string>> ();

        properties.append (new Pair<string,string> (_("System"), label));

        return properties;
    }

    public bool is_architecture_compatible (string architecture) {
        return os_media == null || // Unknown media
               os_media.architecture == architecture ||
               (os_media.architecture == "i386" && architecture == "i686") ||
               (os_media.architecture == "i386" && architecture == "x86_64") ||
               (os_media.architecture == "i686" && architecture == "x86_64");
    }

    protected void add_cd_config (Domain         domain,
                                  DomainDiskType type,
                                  string         iso_path,
                                  string         device_name,
                                  bool           mandatory = false) {
        var disk = new DomainDisk ();

        disk.set_type (type);
        disk.set_guest_device_type (DomainDiskGuestDeviceType.CDROM);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("raw");
        disk.set_target_dev (device_name);
        disk.set_source (iso_path);
        disk.set_target_bus (DomainDiskBus.IDE);
        if (mandatory)
            disk.set_startup_policy (DomainDiskStartupPolicy.MANDATORY);

        domain.add_device (disk);
    }

    private async GUdev.Device? get_device_from_path (string path, Client client, Cancellable? cancellable) {
        try {
            var mount_dir = File.new_for_commandline_arg (path);
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

        return client.query_by_device_file (device_file);
    }

    private void get_media_info_from_device (GUdev.Device device, OSDatabase os_db) throws OSDatabaseError {
        if (!device.get_property_as_boolean ("OSINFO_BOOTABLE"))
            throw new OSDatabaseError.NON_BOOTABLE ("Media %s is not bootable.", device_file);

        label = device.get_property ("ID_FS_LABEL");

        var os_id = device.get_property ("OSINFO_INSTALLER") ?? device.get_property ("OSINFO_LIVE");

        if (os_id != null) {
            os = os_db.get_os_by_id (os_id);

            var media_id = device.get_property ("OSINFO_MEDIA");
            if (media_id != null)
                os_media = os_db.get_media_by_id (os, media_id);
        }
    }

    private void setup_label (string? label = null) {
        if (label != null)
            this.label = label;
        else if (os != null)
            this.label = os.get_name ();
        else {
            // No appropriate label? :( Lets just use filename then
            this.label = Path.get_basename (device_file);

            return;
        }
    }
}
