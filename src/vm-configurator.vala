// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVirConfig;

private class Boxes.VMConfigurator {
    private const string BOXES_NS = "boxes";
    private const string BOXES_NS_URI = "http://live.gnome.org/Boxes/";
    private const string LIVE_STATE = "live";
    private const string INSTALLATION_STATE = "installation";
    private const string INSTALLED_STATE = "installed";
    private const string LIVE_XML = "<os-state>" + LIVE_STATE + "</os-state>";
    private const string INSTALLATION_XML = "<os-state>" + INSTALLATION_STATE + "</os-state>";
    private const string INSTALLED_XML = "<os-state>" + INSTALLED_STATE + "</os-state>";

    public Domain create_domain_config (InstallerMedia install_media, string name, string target_path) {
        var domain = new Domain ();
        domain.name = name;

        var xml = (install_media.live) ? LIVE_XML : INSTALLATION_XML;

        try {
            domain.set_custom_xml (xml, BOXES_NS, BOXES_NS_URI);
        } catch (GLib.Error error) { assert_not_reached (); /* We are so screwed if this happens */ }

        domain.memory = install_media.resources.ram / KIBIBYTES;
        domain.vcpu = install_media.resources.n_cpus;
        domain.set_virt_type (DomainVirtType.KVM);

        set_os_config (domain, install_media);

        domain.set_features ({ "acpi", "apic", "pae" });
        var clock = new DomainClock ();
        if (install_media.os != null && install_media.os.short_id.contains ("win"))
            clock.set_offset (DomainClockOffset.LOCALTIME);
        else
            clock.set_offset (DomainClockOffset.UTC);
        domain.set_clock (clock);

        set_target_media_config (domain, target_path, install_media);
        set_unattended_disk_config (domain, install_media);
        set_source_media_config (domain, install_media);

        var graphics = new DomainGraphicsSpice ();
        graphics.set_autoport (true);
        if (install_media is UnattendedInstaller) {
            var unattended = install_media as UnattendedInstaller;

            // If guest requires password, we let it take care of authentications and free the user from one
            // authentication layer.
            if (unattended.express_install && !unattended.password_mandatory && unattended.password != "")
                graphics.set_password (unattended.password);
        }
        domain.add_device (graphics);

        // SPICE agent channel. This is needed for features like copy&paste between host and guest etc to work.
        var channel = new DomainChannel ();
        channel.set_target_type (DomainChannelTargetType.VIRTIO);
        channel.set_target_name ("com.redhat.spice.0");
        var vmc = new DomainChardevSourceSpiceVmc ();
        channel.set_source (vmc);
        domain.add_device (channel);

        set_video_config (domain, install_media);
        set_sound_config (domain, install_media);
        set_tablet_config (domain, install_media);

        domain.set_lifecycle (DomainLifecycleEvent.ON_POWEROFF, DomainLifecycleAction.DESTROY);
        domain.set_lifecycle (DomainLifecycleEvent.ON_REBOOT, DomainLifecycleAction.DESTROY);
        domain.set_lifecycle (DomainLifecycleEvent.ON_CRASH, DomainLifecycleAction.DESTROY);

        var console = new DomainConsole ();
        console.set_source (new DomainChardevSourcePty ());
        domain.add_device (console);

        var iface = new DomainInterfaceUser ();
        domain.add_device (iface);

        return domain;
    }

    public void post_install_setup (Domain domain) {
        try {
            domain.set_custom_xml (INSTALLED_XML, BOXES_NS, BOXES_NS_URI);
        } catch (GLib.Error error) { assert_not_reached (); /* We are so screwed if this happens */ }
        set_os_config (domain);
        domain.set_lifecycle (DomainLifecycleEvent.ON_REBOOT, DomainLifecycleAction.RESTART);

        // Make source (installer/live media) optional
        var devices = domain.get_devices ();
        foreach (var device in devices) {
            if (!(device is DomainDisk))
                continue;

            // The ideal solution would be to automatically remove the floppy after installation but thats not as
            // trivial as it sounds since some OSs need express install data after (e.g during first-boot setup).
            var disk = device as DomainDisk;
            var disk_type = disk.get_guest_device_type ();
            if (disk_type == DomainDiskGuestDeviceType.CDROM || disk_type == DomainDiskGuestDeviceType.FLOPPY)
                disk.set_startup_policy (DomainDiskStartupPolicy.OPTIONAL);
        }

        domain.set_devices (devices);
    }

    public bool is_install_config (Domain domain) {
        return get_os_state (domain) == INSTALLATION_STATE;
    }

    public bool is_live_config (Domain domain) {
        return get_os_state (domain) == LIVE_STATE;
    }

    public StorageVol create_volume_config (string name, int64 storage) throws GLib.Error {
        var volume = new StorageVol ();
        volume.set_name (name);
        volume.set_capacity (storage);
        var target = new StorageVolTarget ();
        target.set_format ("qcow2");
        var permissions = get_default_permissions ();
        target.set_permissions (permissions);
        volume.set_target (target);

        return volume;
    }

    public StoragePool get_pool_config () throws GLib.Error {
        var pool_path = get_user_pkgdata ("images");
        ensure_directory (pool_path);

        var pool = new StoragePool ();
        pool.set_pool_type (StoragePoolType.DIR);
        pool.set_name (Config.PACKAGE_TARNAME);

        var source = new StoragePoolSource ();
        source.set_directory (pool_path);
        pool.set_source (source);

        var target = new StoragePoolTarget ();
        target.set_path (pool_path);
        var permissions = get_default_permissions ();
        target.set_permissions (permissions);
        pool.set_target (target);

        return pool;
    }

    private void set_target_media_config (Domain domain, string target_path, InstallerMedia install_media) {
        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_guest_device_type (DomainDiskGuestDeviceType.DISK);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("qcow2");
        disk.set_source (target_path);
        disk.set_driver_cache (DomainDiskCacheType.NONE);
        var device = get_os_device_by_prop (install_media.os, DEVICE_PROP_NAME, "virtio-block");
        if (device != null) {
            disk.set_target_bus (DomainDiskBus.VIRTIO);
            disk.set_target_dev ("vda");
        } else {
            disk.set_target_bus (DomainDiskBus.IDE);
            disk.set_target_dev ("hda");
        }

        domain.add_device (disk);
    }

    private void set_source_media_config (Domain domain, InstallerMedia install_media) {
        var disk = new DomainDisk ();
        disk.set_guest_device_type (DomainDiskGuestDeviceType.CDROM);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("raw");
        disk.set_source (install_media.device_file);
        disk.set_target_dev ("hdc");
        disk.set_target_bus (DomainDiskBus.IDE);
        disk.set_startup_policy (DomainDiskStartupPolicy.MANDATORY);

        if (install_media.from_image)
            disk.set_type (DomainDiskType.FILE);
        else
            disk.set_type (DomainDiskType.BLOCK);

        domain.add_device (disk);
    }

    private void set_unattended_disk_config (Domain domain, InstallerMedia install_media) {
        if (!(install_media is UnattendedInstaller))
            return;

        var disk = (install_media as UnattendedInstaller).get_unattended_disk_config ();
        if (disk == null)
            return;

        domain.add_device (disk);
    }

    private void set_os_config (Domain domain, InstallerMedia? install_media = null) {
        var os = new DomainOs ();
        os.set_os_type (DomainOsType.HVM);
        os.set_arch ("x86_64");

        var boot_devices = new GLib.List<DomainOsBootDevice> ();
        if (install_media != null) {
            set_direct_boot_params (os, install_media);
            boot_devices.append (DomainOsBootDevice.CDROM);
        }
        boot_devices.append (DomainOsBootDevice.HD);
        os.set_boot_devices (boot_devices);

        domain.set_os (os);
    }

    private void set_direct_boot_params (DomainOs os, InstallerMedia install_media) {
        if (!(install_media is UnattendedInstaller))
            return;

        (install_media as UnattendedInstaller).set_direct_boot_params (os);
    }

    private void set_video_config (Domain domain, InstallerMedia install_media) {
        var video = new DomainVideo ();
        var device = get_os_device_by_prop (install_media.os, DEVICE_PROP_CLASS, "video");
        var model = (device != null)? get_enum_value (device.get_name (), typeof (DomainVideoModel)) :
                                      DomainVideoModel.QXL;
        return_if_fail (model != -1);
        video.set_model ((DomainVideoModel) model);

        domain.add_device (video);
    }

    private void set_sound_config (Domain domain, InstallerMedia install_media) {
        var sound = new DomainSound ();
        var device = get_os_device_by_prop (install_media.os, DEVICE_PROP_CLASS, "audio");
        var model = (device != null)? get_enum_value (device.get_name (), typeof (DomainSoundModel)) :
                                      DomainSoundModel.AC97;
        return_if_fail (model != -1);
        sound.set_model ((DomainSoundModel) model);

        domain.add_device (sound);
    }

    private void set_tablet_config (Domain domain, InstallerMedia install_media) {
        var device = get_os_device_by_prop (install_media.os, DEVICE_PROP_NAME, "tablet");
        if (device == null)
            return;

        var input = new DomainInput ();
        var bus = get_enum_value (device.get_bus_type (), typeof (DomainInputBus));
        return_if_fail (bus != -1);
        input.set_bus ((DomainInputBus) bus);
        input.set_device_type (DomainInputDeviceType.TABLET);

        domain.add_device (input);
    }

    private StoragePermissions get_default_permissions () {
        var permissions = new StoragePermissions ();

        permissions.set_owner ((uint) Posix.getuid ());
        permissions.set_group ((uint) Posix.getgid ());
        permissions.set_mode (744);

        return permissions;
    }

    private string? get_os_state (Domain domain) {
        var xml = domain.get_custom_xml (BOXES_NS_URI);
        if (xml != null) {
            var reader = new Xml.TextReader.for_memory ((char []) xml.data,
                                                        xml.length,
                                                        BOXES_NS_URI,
                                                        null,
                                                        Xml.ParserOption.COMPACT);
            do {
                if (reader.name () == "boxes:os-state")
                    return reader.read_string ();
            } while (reader.next () == 1);
        }

        warning ("Failed to find OS state for domain '%s'.", domain.get_name ());

        return null;
    }
}
