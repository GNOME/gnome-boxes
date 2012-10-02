// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVirConfig;

private errordomain Boxes.VMConfiguratorError {
    NO_GUEST_CAPS,
}

private class Boxes.VMConfigurator {
    private const string BOXES_NS = "boxes";
    private const string BOXES_NS_URI = "http://live.gnome.org/Boxes/";
    private const string LIVE_STATE = "live";
    private const string INSTALLATION_STATE = "installation";
    private const string INSTALLED_STATE = "installed";
    private const string LIVE_XML = "<os-state>" + LIVE_STATE + "</os-state>";
    private const string INSTALLATION_XML = "<os-state>" + INSTALLATION_STATE + "</os-state>";
    private const string INSTALLED_XML = "<os-state>" + INSTALLED_STATE + "</os-state>";

    public static Domain create_domain_config (InstallerMedia install_media, string target_path, Capabilities caps)
                                        throws VMConfiguratorError {
        var domain = new Domain ();

        var xml = (install_media.live) ? LIVE_XML : INSTALLATION_XML;

        try {
            domain.set_custom_xml (xml, BOXES_NS, BOXES_NS_URI);
        } catch (GLib.Error error) { assert_not_reached (); /* We are so screwed if this happens */ }

        var best_caps = get_best_guest_caps (caps, install_media);
        domain.memory = install_media.resources.ram / KIBIBYTES;
        set_cpu_config (domain, caps);

        var virt_type = guest_kvm_enabled (best_caps) ? DomainVirtType.KVM : DomainVirtType.QEMU;
        domain.set_virt_type (virt_type);

        set_os_config (domain, install_media, best_caps);

        string[] features = {};
        if (guest_supports_feature (best_caps, "acpi"))
            features += "acpi";
        if (guest_supports_feature (best_caps, "apic"))
            features += "apic";
        if (guest_supports_feature (best_caps, "pae"))
            features += "pae";
        domain.set_features (features);

        var clock = new DomainClock ();
        if (install_media.os != null && install_media.os.short_id.contains ("win"))
            clock.set_offset (DomainClockOffset.LOCALTIME);
        else
            clock.set_offset (DomainClockOffset.UTC);

        DomainTimer timer = new DomainTimerRtc ();
        timer.set_tick_policy (DomainTimerTickPolicy.CATCHUP);
        clock.add_timer (timer);
        timer = new DomainTimerPit ();
        timer.set_tick_policy (DomainTimerTickPolicy.DELAY);
        clock.add_timer (timer);
        domain.set_clock (clock);

        set_target_media_config (domain, target_path, install_media);
        install_media.setup_domain_config (domain);

        var graphics = new DomainGraphicsSpice ();
        graphics.set_autoport (true);
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

    public static void post_install_setup (Domain domain) {
        set_post_install_os_config (domain);
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

    public static void mark_as_installed (Domain domain) {
        try {
            domain.set_custom_xml (INSTALLED_XML, BOXES_NS, BOXES_NS_URI);
        } catch (GLib.Error error) { assert_not_reached (); /* We are so screwed if this happens */ }
    }

    public static bool is_install_config (Domain domain) {
        return get_os_state (domain) == INSTALLATION_STATE;
    }

    public static bool is_live_config (Domain domain) {
        return get_os_state (domain) == LIVE_STATE;
    }

    public static StorageVol create_volume_config (string name, int64 storage) throws GLib.Error {
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

    public static StoragePool get_pool_config () throws GLib.Error {
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

    private static void set_cpu_config (Domain domain, Capabilities caps) {
        var topology = caps.get_host ().get_cpu ().get_topology ();

        if (topology == null)
            return;

        domain.vcpu = topology.get_sockets () * topology.get_cores () * topology.get_threads ();

        var cpu = new DomainCpu ();
        cpu.set_mode (DomainCpuMode.HOST_MODEL);
        cpu.set_topology (topology);
        domain.set_cpu (cpu);
    }

    private static void set_target_media_config (Domain domain, string target_path, InstallerMedia install_media) {
        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_guest_device_type (DomainDiskGuestDeviceType.DISK);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("qcow2");
        disk.set_source (target_path);
        disk.set_driver_cache (DomainDiskCacheType.NONE);

        if (install_media.supports_virtio_disk) {
            debug ("Using virtio controller for the main disk");
            disk.set_target_bus (DomainDiskBus.VIRTIO);
            disk.set_target_dev ("vda");
        } else {
            debug ("Using IDE controller for the main disk");
            disk.set_target_bus (DomainDiskBus.IDE);
            disk.set_target_dev ("hda");
        }

        domain.add_device (disk);
    }

    private static void set_post_install_os_config (Domain domain) {
        var os = new DomainOs ();
        os.set_os_type (DomainOsType.HVM);

        var old_os = domain.get_os ();
        var boot_devices = old_os.get_boot_devices ();
        boot_devices.remove (DomainOsBootDevice.CDROM);
        os.set_boot_devices (boot_devices);

        os.set_arch (old_os.get_arch ());

        domain.set_os (os);
    }

    private static void set_os_config (Domain domain, InstallerMedia install_media, CapabilitiesGuest guest_caps) {
        var os = new DomainOs ();
        os.set_os_type (DomainOsType.HVM);
        os.set_arch (guest_caps.get_arch ().get_name ());

        var boot_devices = new GLib.List<DomainOsBootDevice> ();
        install_media.set_direct_boot_params (os);
        boot_devices.append (DomainOsBootDevice.CDROM);
        boot_devices.append (DomainOsBootDevice.HD);
        os.set_boot_devices (boot_devices);

        domain.set_os (os);
    }

    private static void set_video_config (Domain domain, InstallerMedia install_media) {
        var video = new DomainVideo ();
        var device = get_os_device_by_prop (install_media.os, DEVICE_PROP_CLASS, "video");
        var model = (device != null)? get_enum_value (device.get_name (), typeof (DomainVideoModel)) :
                                      DomainVideoModel.QXL;
        return_if_fail (model != -1);
        video.set_model ((DomainVideoModel) model);

        domain.add_device (video);
    }

    private static void set_sound_config (Domain domain, InstallerMedia install_media) {
        var sound = new DomainSound ();
        var device = get_os_device_by_prop (install_media.os, DEVICE_PROP_CLASS, "audio");
        var model = (device != null)? get_enum_value (device.get_name (), typeof (DomainSoundModel)) :
                                      DomainSoundModel.AC97;
        return_if_fail (model != -1);
        sound.set_model ((DomainSoundModel) model);

        domain.add_device (sound);
    }

    private static void set_tablet_config (Domain domain, InstallerMedia install_media) {
        var input = new DomainInput ();
        input.set_device_type (DomainInputDeviceType.TABLET);

        domain.add_device (input);
    }

    private static StoragePermissions get_default_permissions () {
        var permissions = new StoragePermissions ();

        permissions.set_owner ((uint) Posix.getuid ());
        permissions.set_group ((uint) Posix.getgid ());
        permissions.set_mode (744);

        return permissions;
    }

    private static string? get_os_state (Domain domain) {
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

        debug ("no Boxes OS state for domain '%s'.", domain.get_name ());

        return null;
    }

    private static CapabilitiesGuest get_best_guest_caps (Capabilities caps, InstallerMedia install_media)
                                                          throws VMConfiguratorError {
        var guests_caps = caps.get_guests ();

        // First find all compatible guest caps
        var compat_guests_caps = new GLib.List<CapabilitiesGuest> ();
        foreach (var guest_caps in guests_caps) {
            var guest_arch = guest_caps.get_arch ().get_name ();

            if (install_media.is_architecture_compatible (guest_arch))
                compat_guests_caps.append (guest_caps);
        }

        // Now lets see if there is any KVM-enabled guest caps
        foreach (var guest_caps in compat_guests_caps)
            if (guest_kvm_enabled (guest_caps))
                return guest_caps;

        // No KVM-enabled guest caps :( We at least need Qemu
        foreach (var guest_caps in compat_guests_caps)
            if (guest_is_qemu (guest_caps))
                return guest_caps;

        // No guest caps or none compatible
        // FIXME: Better error messsage than this please?
        throw new VMConfiguratorError.NO_GUEST_CAPS (_("Incapable host system"));
    }

    private static bool guest_kvm_enabled (CapabilitiesGuest guest_caps) {
        var arch = guest_caps.get_arch ();
        foreach (var domain in arch.get_domains ())
            if (domain.get_virt_type () == DomainVirtType.KVM)
                return true;

        return false;
    }

    private static bool guest_is_qemu (CapabilitiesGuest guest_caps) {
        var arch = guest_caps.get_arch ();
        foreach (var domain in arch.get_domains ())
            if (domain.get_virt_type () == DomainVirtType.QEMU)
                return true;

        return false;
    }

    private static bool guest_supports_feature (CapabilitiesGuest guest_caps, string feature_name) {
        var supports = false;

        foreach (var feature in guest_caps.get_features ())
            if (feature_name == feature.get_name ()) {
                supports = true;

                break;
            }

        return supports;
    }
}
