// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVirConfig;

private errordomain Boxes.VMConfiguratorError {
    NO_GUEST_CAPS,
}

private class Boxes.VMConfigurator {
    private const string BOXES_NS = "boxes";
    /* This should not reference PACKAGE_URL, which could change in the
       future, but this is effectively part of boxes XML API */
    private const string BOXES_NS_URI = "https://wiki.gnome.org/Apps/Boxes";
    private const string BOXES_OLD_NS_URI = "http://live.gnome.org/Boxes/";
    private const string WEBDAV_CHANNEL_URI = "org.spice-space.webdav.0";
    private const string BOXES_XML = "<gnome-boxes>%s</gnome-boxes>";
    private const string LIVE_STATE = "live";
    private const string INSTALLATION_STATE = "installation";
    private const string IMPORT_STATE = "importing";
    private const string LIBVIRT_SYS_IMPORT_STATE = "libvirt-system-importing";
    private const string LIBVIRT_CLONING_STATE = "libvirt-cloning";
    private const string INSTALLED_STATE = "installed";
    private const string LIVE_XML = "<os-state>" + LIVE_STATE + "</os-state>";
    private const string INSTALLATION_XML = "<os-state>" + INSTALLATION_STATE + "</os-state>";
    private const string IMPORT_XML = "<os-state>" + IMPORT_STATE + "</os-state>";
    private const string LIBVIRT_SYS_IMPORT_XML = "<os-state>" + LIBVIRT_SYS_IMPORT_STATE + "</os-state>";
    private const string LIBVIRT_CLONING_XML = "<os-state>" + LIBVIRT_CLONING_STATE + "</os-state>";
    private const string INSTALLED_XML = "<os-state>" + INSTALLED_STATE + "</os-state>";

    private const string OS_ID_XML = "<os-id>%s</os-id>";
    private const string MEDIA_ID_XML = "<media-id>%s</media-id>";
    private const string MEDIA_XML = "<media>%s</media>";
    private const string NUM_REBOOTS_XML = "<num-reboots>%u</num-reboots>";

    private const string LIBOSINFO_NS = "libosinfo";
    private const string LIBOSINFO_NS_URI = "http://libosinfo.org/xmlns/libvirt/domain/1.0";
    private const string LIBOSINFO_XML = "<libosinfo>%s</libosinfo>";
    private const string LIBOSINFO_OS_ID_XML = "<os id=\"%s\"/>";

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
        timer = new DomainTimerHpet ();
        timer.set_present (false);
        clock.add_timer (timer);
        domain.set_clock (clock);

        if (install_media is InstalledMedia)
            target_path = install_media.device_file;

        set_target_media_config (domain, target_path, install_media);
        install_media.setup_domain_config (domain);

        bool accel3d;
        set_video_config (domain, install_media, out accel3d);
        var graphics = create_graphics_device (accel3d);
        domain.add_device (graphics);

        // SPICE agent channel. This is needed for features like copy&paste between host and guest etc to work.
        var channel = new DomainChannel ();
        channel.set_target_type (DomainChannelTargetType.VIRTIO);
        channel.set_target_name ("com.redhat.spice.0");
        var vmc = new DomainChardevSourceSpiceVmc ();
        channel.set_source (vmc);
        domain.add_device (channel);

        // Webdav channel. This is needed for the shared folder feature to work.
        var webdav_channel = create_webdav_channel ();
        domain.add_device (webdav_channel);

        add_usb_support (domain);
#if !FLATPAK
        add_smartcard_support (domain);
#endif

        set_sound_config (domain, install_media);
        set_tablet_config (domain, install_media);
        set_mouse_config (domain, install_media);
        set_keyboard_config (domain, install_media);

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

        var supports_virtio_net = install_media.supports_virtio_net || install_media.supports_virtio1_net;
        var iface = create_network_interface (domain,
                                              is_libvirt_bridge_net_available (),
                                              supports_virtio_net);
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

    public static bool is_libvirt_system_import_config (Domain domain) {
        return get_os_state (domain) == LIBVIRT_SYS_IMPORT_STATE;
    }

    public static bool is_libvirt_cloning_config (Domain domain) {
        return get_os_state (domain) == LIBVIRT_CLONING_STATE;
    }

    public static bool is_boxes_installed (Domain domain) {
        return get_os_state (domain) == INSTALLED_STATE;
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
        var str = get_libosinfo_os_id (domain);
        if (str == null)
            str = get_custom_xml_node (domain, "os-id");

        return str;
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
        var cpu_caps = caps.get_host ().get_cpu ();
        var topology = cpu_caps.get_topology ();

        if (topology == null)
            return;

        domain.vcpu = topology.get_sockets () * topology.get_cores () * topology.get_threads ();

        var cpu = new DomainCpu ();
        cpu.set_mode (DomainCpuMode.HOST_PASSTHROUGH);
        cpu.set_topology (topology);

        domain.set_cpu (cpu);
    }

    public static async void update_existing_domain (Domain          domain,
                                                     GVir.Connection connection) {
        if (!boxes_created_domain (domain))
            return;

        try {
            var cpu = domain.get_cpu ();
            if (cpu != null && is_boxes_installed (domain)) {
                var capabilities = yield connection.get_capabilities_async (null);
                set_cpu_config (domain, capabilities);
            }
        } catch (GLib.Error e) {
            warning ("Failed to update CPU config for '%s': %s", domain.name, e.message);
        }

        GLib.List<GVirConfig.DomainDevice> devices = null;
        DomainInterface iface = null;
        DomainGraphicsSpice graphics = null;
        bool accel3d = false;
        DomainChannel channel_webdav = null;
        foreach (var device in domain.get_devices ()) {
            if (device is DomainInterface)
                iface = device as DomainInterface;
            else if (device is DomainGraphicsSpice)
                graphics = device as DomainGraphicsSpice;
            else if (device is DomainVideo) {
                var model = (device as DomainVideo).get_model ();
                accel3d = (model == DomainVideoModel.VIRTIO);
                devices.prepend (device);
            }
            else if (device is DomainChannel) {
                var device_channel = device as DomainChannel;
                if (device_channel.get_target_name () == WEBDAV_CHANNEL_URI)
                    channel_webdav = device_channel;
                devices.prepend (device);
            }
            else
                devices.prepend (device);
        }

        // If user interface device was found and it needs to be bridged
        if (iface != null) {
            var bridge = is_libvirt_bridge_net_available ();
            if (bridge && (iface is DomainInterfaceUser)) {
                var virtio = iface.get_model () == "virtio";

                devices.prepend (create_network_interface (domain, bridge, virtio));
            } else {
                devices.prepend (iface);
            }
        }

        if (graphics != null)
            devices.prepend (create_graphics_device (accel3d));
        if (channel_webdav == null)
            devices.prepend (create_webdav_channel ());

        devices.reverse ();
        domain.set_devices (devices);
    }

    public static void set_target_media_config (Domain         domain,
                                                string         target_path,
                                                InstallerMedia install_media,
                                                uint8          dev_index = 0) {
        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_guest_device_type (DomainDiskGuestDeviceType.DISK);
        disk.set_driver_name ("qemu");
        disk.set_driver_format (DomainDiskFormat.QCOW2);
        disk.set_source (target_path);
        disk.set_driver_cache (DomainDiskCacheType.WRITEBACK);

        var dev_letter_str = ((char) (dev_index + 97)).to_string ();
        if (install_media.supports_virtio_disk || install_media.supports_virtio1_disk) {
            debug ("Using virtio controller for the main disk");
            disk.set_target_bus (DomainDiskBus.VIRTIO);
            disk.set_target_dev ("vd" + dev_letter_str);
        } else {
            if (install_media.prefers_q35) {
                debug ("Using SATA controller for the main disk");
                disk.set_target_bus (DomainDiskBus.SATA);
            } else {
                debug ("Using IDE controller for the main disk");
                disk.set_target_bus (DomainDiskBus.IDE);
            }
            disk.set_target_dev ("hd" + dev_letter_str);
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
        os.set_machine (old_os.get_machine ());

        domain.set_os (os);
    }

    private static void set_os_config (Domain domain, InstallerMedia install_media, CapabilitiesGuest guest_caps) {
        var os = new DomainOs ();
        os.set_os_type (DomainOsType.HVM);
        os.set_arch (guest_caps.get_arch ().get_name ());
        if (install_media.prefers_q35)
            os.set_machine ("q35");

        var boot_devices = new GLib.List<DomainOsBootDevice> ();
        install_media.set_direct_boot_params (os);
        boot_devices.append (DomainOsBootDevice.CDROM);
        boot_devices.append (DomainOsBootDevice.HD);
        os.set_boot_devices (boot_devices);

        domain.set_os (os);
    }

    private static void set_video_config (Domain domain, InstallerMedia install_media, out bool accel3d) {
        var video = new DomainVideo ();
        video.set_model (DomainVideoModel.QXL);

        var device = find_device_by_prop (install_media.supported_devices, DEVICE_PROP_NAME, "virtio1.0-gpu");
        accel3d = (device != null);
        if (accel3d) {
            video.set_model (DomainVideoModel.VIRTIO);
            video.set_accel3d (accel3d);
        }

        domain.add_device (video);
    }

    private static DomainSoundModel get_sound_model (InstallerMedia install_media) {
        if (install_media.prefers_ich9)
            return (DomainSoundModel) DomainSoundModel.ICH9;

        var device = find_device_by_prop (install_media.supported_devices, DEVICE_PROP_CLASS, "audio");
        if (device == null)
            return (DomainSoundModel) DomainSoundModel.ICH6;

        var osinfo_name = device.get_name ();
        var libvirt_name = "";

        if (osinfo_name == "ich9-hda")
            libvirt_name = "ich9";
        else if (osinfo_name == "ich6")
            libvirt_name = "ich6";
        else if (osinfo_name == "ac97")
            libvirt_name = "ac97";
        else if (osinfo_name == "pcspk")
            libvirt_name = "pcspk";
        else if (osinfo_name == "es1370")
            libvirt_name = "es1370";
        else if (osinfo_name == "sb16")
            libvirt_name = "sb16";

        var model = get_enum_value (libvirt_name, typeof (DomainSoundModel));
        return_if_fail (model != -1);
        return (DomainSoundModel) model;
    }

    private static void set_sound_config (Domain domain, InstallerMedia install_media) {
        var sound = new DomainSound ();
        sound.set_model (get_sound_model (install_media));

        domain.add_device (sound);
    }

    private static void set_tablet_config (Domain domain, InstallerMedia install_media) {
        var device = find_device_by_prop (install_media.supported_devices, DEVICE_PROP_NAME, "tablet");
        if (device == null)
            return;

        var input = new DomainInput ();
        input.set_device_type (DomainInputDeviceType.TABLET);
        input.set_bus (DomainInputBus.USB);

        domain.add_device (input);
    }

    private static void set_mouse_config (Domain domain, InstallerMedia install_media) {
        set_input_config (domain, DomainInputDeviceType.MOUSE);
    }

    private static void set_keyboard_config (Domain domain, InstallerMedia install_media) {
        set_input_config (domain, DomainInputDeviceType.KEYBOARD);
    }

    private static void set_input_config (Domain domain, DomainInputDeviceType device_type) {
        var input = new DomainInput ();
        input.set_device_type (device_type);
        input.set_bus (DomainInputBus.PS2);

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

    private static string? get_libosinfo_os_id (Domain domain) {
        var ns_uri = LIBOSINFO_NS_URI;
        var xml = domain.get_custom_xml (ns_uri);
        if (xml == null)
            return null;

        var reader = new Xml.TextReader.for_memory ((char []) xml.data,
                                                    xml.length,
                                                    ns_uri,
                                                    null,
                                                    Xml.ParserOption.COMPACT);

        reader.next (); // Go to first node

        var node = reader.expand ();
        if (node != null) {
            if (node->name == "libosinfo")
                node = node->children;

            while (node != null) {
                if (node->name == "os")
                    return node->get_prop ("id");

                node = node->next;
            }
        }

        return null;
    }

    private static string? get_custom_xml_node (Domain domain, string node_name) {
        var ns_uri = BOXES_NS_URI;
        var xml = domain.get_custom_xml (ns_uri);
        if (xml == null) {
            ns_uri = BOXES_OLD_NS_URI;
            xml = domain.get_custom_xml (ns_uri);
        }

        if (xml != null) {
            var reader = new Xml.TextReader.for_memory ((char []) xml.data,
                                                        xml.length,
                                                        ns_uri,
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

    private static bool boxes_created_domain (Domain domain) {
        var xml = domain.get_custom_xml (BOXES_NS_URI);
        if (xml == null)
            xml = domain.get_custom_xml (BOXES_OLD_NS_URI);

        return (xml != null);
    }

    private static void update_custom_xml (Domain domain,
                                           InstallerMedia? install_media,
                                           uint num_reboots = 0,
                                           bool installed = false) {
        return_if_fail (install_media != null || installed);
        string custom_xml;
        string custom_libosinfo_xml = null;

        if (installed)
            custom_xml = INSTALLED_XML;
        else if (install_media is LibvirtClonedMedia)
            custom_xml = LIBVIRT_CLONING_XML;
        else if (install_media is LibvirtMedia)
            custom_xml = LIBVIRT_SYS_IMPORT_XML;
        else if (install_media is InstalledMedia)
            custom_xml = IMPORT_XML;
        else
            custom_xml = (install_media.live) ? LIVE_XML : INSTALLATION_XML;

        if (install_media != null) {
            if (install_media.os != null)
                custom_libosinfo_xml = Markup.printf_escaped (LIBOSINFO_OS_ID_XML, install_media.os.id);
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

        if (custom_libosinfo_xml != null) {
            custom_libosinfo_xml = LIBOSINFO_XML.printf (custom_libosinfo_xml);
            try {
                domain.set_custom_xml_ns_children (custom_libosinfo_xml, LIBOSINFO_NS, LIBOSINFO_NS_URI);
            } catch (GLib.Error error) { assert_not_reached (); /* We are so screwed if this happens */ }
        }
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

    public static DomainInterface create_network_interface (Domain domain, bool bridge, bool virtio) {
        DomainInterface iface;

        if (bridge) {
            debug ("Creating bridge network device for %s", domain.get_name ());
            var bridge_iface = new DomainInterfaceBridge ();
            bridge_iface.set_source ("virbr0");
            iface = bridge_iface;
        } else {
            debug ("Creating user network device for %s", domain.get_name ());
            iface = new DomainInterfaceUser ();
        }

        if (virtio)
            iface.set_model ("virtio");

        return iface;
    }

    public static DomainGraphicsSpice create_graphics_device (bool accel3d = false) {
        var graphics = new DomainGraphicsSpice ();
        graphics.set_autoport (false);
        graphics.set_gl (accel3d);
        graphics.set_image_compression (DomainGraphicsSpiceImageCompression.OFF);

        return graphics;
    }

    public static DomainChannel create_webdav_channel () {
        var channel_webdav = new DomainChannel ();
        channel_webdav.set_target_type (DomainChannelTargetType.VIRTIO);
        channel_webdav.set_target_name (WEBDAV_CHANNEL_URI);

        var spice_port = new DomainChardevSourceSpicePort ();
        spice_port.set_channel (WEBDAV_CHANNEL_URI);
        channel_webdav.set_source (spice_port);

        return channel_webdav;
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

    private static CapabilitiesGuest get_best_guest_caps (Capabilities caps, InstallerMedia install_media)
                                                          throws VMConfiguratorError {
        var guests_caps = caps.get_guests ();
        // Ensure we have the best caps on the top
        guests_caps.sort ((caps_a, caps_b) => {
            var arch_a = caps_a.get_arch ().get_name ();
            var arch_b = caps_b.get_arch ().get_name ();

            if (arch_a == "i686") {
                if (arch_b == "x86_64")
                    return 1;
                else
                    return -1;
            } else if (arch_a == "x86_64") {
                return -1;
            } else if (arch_b == "x86_64" || arch_b == "i686") {
                return 1;
            } else
                return 0;
        });

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
