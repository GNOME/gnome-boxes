// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVirConfig;

private abstract class Boxes.Installer : GLib.Object {
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

    public bool supports_virtio1_disk {
        get {
            return (find_device_by_prop (supported_devices, DEVICE_PROP_NAME, "virtio1.0-block") != null);
        }
    }

    public bool supports_virtio_disk {
        get {
            return (find_device_by_prop (supported_devices, DEVICE_PROP_NAME, "virtio-block") != null);
        }
    }

    public bool supports_virtio1_net {
        get {
            return (find_device_by_prop (supported_devices, DEVICE_PROP_NAME, "virtio1.0-net") != null);
        }
    }

    public bool supports_virtio_net {
        get {
            return (find_device_by_prop (supported_devices, DEVICE_PROP_NAME, "virtio-net") != null);
        }
    }

    public bool supports_virtio_gpu {
        get {
            return (find_device_by_prop (supported_devices, DEVICE_PROP_NAME, "virtio1.0-gpu") != null);
        }
    }

    public bool prefers_q35 {
        get {
            if (os == null)
                return true;

            var device = find_device_by_prop (supported_devices, DEVICE_PROP_NAME, "qemu-x86-q35");
            if (device == null)
                return false;

            if (supports_virtio_net && !supports_virtio1_net)
                return false;

            return true;
        }
    }

    public bool prefers_ich9 {
        get {
            if (!prefers_q35)
                return false;

            var device = find_device_by_prop (supported_devices, DEVICE_PROP_NAME, "ich9-hda");
            if (device == null)
                return false;

            return true;
        }
    }

    public virtual bool live { get; }
    public virtual bool eject_after_install { get; }

    protected string? architecture {
        owned get;
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

    public abstract void setup_post_install_domain_config (Domain domain);

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

    public abstract VMCreator get_vm_creator ();

    protected abstract void add_cd_config (Domain         domain,
                                  DomainDiskType type,
                                  string?        iso_path,
                                  string         device_name,
                                  bool           mandatory = false); 
    
    
    protected abstract void label_setup (string? label = null);


    public abstract async string get_device_file_from_path (string path, Cancellable? cancellable);
  

#if !FLATPAK
    public async GUdev.Device? get_device_from_device_file (string device_file, GUdev.Client client) {
        return client.query_by_device_file (device_file);
    }

    public abstract async void get_media_info_from_device (GUdev.Device device, OSDatabase os_db) throws GLib.Error;
 

    public abstract void get_decoded_udev_properties_for_media (GUdev.Device device,
                                                        string[]     udev_props,
                                                        string[]     media_props,
                                                        Osinfo.Media media);


    public string? get_decoded_udev_property (GUdev.Device device, string property_name) {
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

    public abstract void eject_cdrom_media (Domain domain);

}