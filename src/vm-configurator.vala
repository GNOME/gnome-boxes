// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVirConfig;

private errordomain Boxes.VMConfiguratorError {
    NO_GUEST_CAPS,
}

private class Boxes.VMConfigurator {
    private const string BOXES_NS = "boxes";
    private const string BOXES_NS_URI = "http://live.gnome.org/Boxes/";
    private const string BOXES_XML = "<gnome-boxes>%s</gnome-boxes>";
    private const string LIVE_STATE = "live";
    private const string INSTALLATION_STATE = "installation";
    private const string IMPORT_STATE = "importing";
    private const string INSTALLED_STATE = "installed";
    private const string LIVE_XML = "<os-state>" + LIVE_STATE + "</os-state>";
    private const string INSTALLATION_XML = "<os-state>" + INSTALLATION_STATE + "</os-state>";
    private const string IMPORT_XML = "<os-state>" + IMPORT_STATE + "</os-state>";
    private const string INSTALLED_XML = "<os-state>" + INSTALLED_STATE + "</os-state>";

    private const string OS_ID_XML = "<os-id>%s</os-id>";
    private const string MEDIA_ID_XML = "<media-id>%s</media-id>";
    private const string MEDIA_XML = "<media>%s</media>";
    private const string NUM_REBOOTS_XML = "<num-reboots>%u</num-reboots>";

    public static Domain create_domain_config (InstallerMedia install_media, string target_path, Capabilities caps)
                                        throws VMConfiguratorError {
        var domain = new Domain ();

        setup_custom_xml (domain, install_media);

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
        graphics.set_image_compression (DomainGraphicsSpiceImageCompression.OFF);
        domain.add_device (graphics);

        // SPICE agent channel. This is needed for features like copy&paste between host and guest etc to work.
        var channel = new DomainChannel ();
        channel.set_target_type (DomainChannelTargetType.VIRTIO);
        channel.set_target_name ("com.redhat.spice.0");
        var vmc = new DomainChardevSourceSpiceVmc ();
        channel.set_source (vmc);
        domain.add_device (channel);

        // Only add usb support if we'er 100% sure it works, as it breaks migration (i.e. save) on older qemu
        if (Config.HAVE_USBREDIR)
            add_usb_support (domain);

        if (Config.HAVE_SMARTCARD)
            add_smartcard_support (domain);

        set_video_config (domain, install_media);
        set_sound_config (domain, install_media);
        set_tablet_config (domain, install_media);

        domain.set_lifecycle (DomainLifecycleEvent.ON_POWEROFF, DomainLifecycleAction.DESTROY);
        domain.set_lifecycle (DomainLifecycleEvent.ON_REBOOT, DomainLifecycleAction.DESTROY);
        domain.set_lifecycle (DomainLifecycleEvent.ON_CRASH, DomainLifecycleAction.DESTROY);

        var pm = new DomainPowerManagement ();
        // Disable S3 and S4 states for now due to many issues with it currently in qemu/libvirt
        pm.set_mem_suspend_enabled (false);
        pm.set_disk_suspend_enabled (false);
        domain.set_power_management (pm);
        var console = new DomainConsole ();
        console.set_source (new DomainChardevSourcePty ());
        domain.add_device (console);

        var iface = new DomainInterfaceUser ();
        if (install_media.supports_virtio_net)
            iface.set_model ("virtio");
        domain.add_device (iface);

        return domain;
    }

    public static void post_install_setup (Domain domain, InstallerMedia? install_media) {
        set_post_install_os_config (domain);
        domain.set_lifecycle (DomainLifecycleEvent.ON_REBOOT, DomainLifecycleAction.RESTART);

        if (install_media != null)
            install_media.setup_post_install_domain_config (domain);

        mark_as_installed (domain, install_media);
    }

    public static bool is_install_config (Domain domain) {
        return get_os_state (domain) == INSTALLATION_STATE;
    }

    public static bool is_live_config (Domain domain) {
        return get_os_state (domain) == LIVE_STATE;
    }

    public static bool is_import_config (Domain domain) {
        return get_os_state (domain) == IMPORT_STATE;
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

    public static string? get_os_id (Domain domain) {
        return get_custom_xml_node (domain, "os-id");
    }

    public static string? get_os_media_id (Domain domain) {
        return get_custom_xml_node (domain, "media-id");
    }

    public static string? get_source_media_path (Domain domain) {
        return get_custom_xml_node (domain, "media");
    }

    public static uint get_num_reboots (Domain domain) {
        var str = get_custom_xml_node (domain, "num-reboots");
        return (str != null)? int.parse (str) : 0;
    }

    public static void set_num_reboots (Domain domain, InstallerMedia install_media, uint num_reboots) {
        update_custom_xml (domain, install_media, num_reboots);
    }

    public static void setup_custom_xml (Domain domain, InstallerMedia install_media) {
        update_custom_xml (domain, install_media);
    }

    private static void mark_as_installed (Domain domain, InstallerMedia? install_media) {
        update_custom_xml (domain, install_media, 0, true);
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
        disk.set_driver_format (DomainDiskFormat.QCOW2);
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
        var device = find_device_by_prop (install_media.supported_devices, DEVICE_PROP_CLASS, "video");
        var model = (device != null)? get_enum_value (device.get_name (), typeof (DomainVideoModel)) :
                                      DomainVideoModel.QXL;
        return_if_fail (model != -1);
        video.set_model ((DomainVideoModel) model);

        domain.add_device (video);
    }

    private static void set_sound_config (Domain domain, InstallerMedia install_media) {
        var sound = new DomainSound ();
        var device = find_device_by_prop (install_media.supported_devices, DEVICE_PROP_CLASS, "audio");
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
        return get_custom_xml_node (domain, "os-state");
    }

    private static string? get_custom_xml_node (Domain domain, string node_name) {
        var xml = domain.get_custom_xml (BOXES_NS_URI);
        if (xml != null) {
            var reader = new Xml.TextReader.for_memory ((char []) xml.data,
                                                        xml.length,
                                                        BOXES_NS_URI,
                                                        null,
                                                        Xml.ParserOption.COMPACT);
            reader.next (); // Go to first node

            var node = reader.expand ();
            if (node != null) {
                // Newer configurations have nodes of interest under a toplevel 'gnome-boxes' element
                if (node->name == "gnome-boxes")
                    node = node->children;

                while (node != null) {
                    if (node->name == node_name)
                        return node->children->content;

                    node = node->next;
                }
            }
        }

        debug ("No XML node %s' for domain '%s'.", node_name, domain.get_name ());

        return null;
    }

    private static void update_custom_xml (Domain domain,
                                           InstallerMedia? install_media,
                                           uint num_reboots = 0,
                                           bool installed = false) {
        return_if_fail (install_media != null || installed);
        string custom_xml;

        if (installed)
            custom_xml = INSTALLED_XML;
        else if (install_media is InstalledMedia)
            custom_xml = IMPORT_XML;
        else
            custom_xml = (install_media.live) ? LIVE_XML : INSTALLATION_XML;

        if (install_media != null) {
            if (install_media.os != null)
                custom_xml += Markup.printf_escaped (OS_ID_XML, install_media.os.id);
            if (install_media.os_media != null)
                custom_xml += Markup.printf_escaped (MEDIA_ID_XML, install_media.os_media.id);
            custom_xml += Markup.printf_escaped (MEDIA_XML, install_media.device_file);
        }

        if (num_reboots != 0)
            custom_xml += NUM_REBOOTS_XML.printf (num_reboots);

        custom_xml = BOXES_XML.printf (custom_xml);
        try {
            domain.set_custom_xml (custom_xml, BOXES_NS, BOXES_NS_URI);
        } catch (GLib.Error error) { assert_not_reached (); /* We are so screwed if this happens */ }
    }

    public static void add_smartcard_support (Domain domain) {
        var smartcard = new DomainSmartcardPassthrough ();
        var vmc = new DomainChardevSourceSpiceVmc ();
        smartcard.set_source (vmc);
        domain.add_device (smartcard);
    }

    public static void add_usb_support (Domain domain) {
        // 4 USB redirection channels
        for (int i = 0; i < 4; i++) {
            var usb_redir = new DomainRedirdev ();
            usb_redir.set_bus (DomainRedirdevBus.USB);
            var vmc = new DomainChardevSourceSpiceVmc ();
            usb_redir.set_source (vmc);
            domain.add_device (usb_redir);
        }

        // USB controllers
        var master_controller = create_usb_controller (DomainControllerUsbModel.ICH9_EHCI1);
        domain.add_device (master_controller);
        var controller = create_usb_controller (DomainControllerUsbModel.ICH9_UHCI1, master_controller, 0, 0);
        domain.add_device (controller);
        controller = create_usb_controller (DomainControllerUsbModel.ICH9_UHCI2, master_controller, 0, 2);
        domain.add_device (controller);
        controller = create_usb_controller (DomainControllerUsbModel.ICH9_UHCI3, master_controller, 0, 4);
        domain.add_device (controller);
    }

    private static DomainControllerUsb create_usb_controller (DomainControllerUsbModel model,
                                                              DomainControllerUsb?     master = null,
                                                              uint                     index = 0,
                                                              uint                     start_port = 0) {
        var controller = new DomainControllerUsb ();
        controller.set_model (model);
        controller.set_index (index);
        if (master != null)
            controller.set_master (master, start_port);

        return controller;
    }

    // Remove all existing usb controllers. This is used when upgrading from the old usb1 controllers to usb2
    public static void remove_usb_controllers (Domain domain) throws Boxes.Error {
        GLib.List<GVirConfig.DomainDevice> devices = null;
        foreach (var device in domain.get_devices ()) {
            if (!(device is DomainControllerUsb)) {
                devices.prepend (device);
            }
        }
        devices.reverse ();
        domain.set_devices (devices);
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
