// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVirConfig;

private class Boxes.VMConfigurator {
    public Domain create_domain_config (InstallerMedia install_media,
                                        string         name,
                                        string         target_path,
                                        Resources      resources) {

        var domain = new Domain ();
        domain.name = name;
        domain.memory = resources.ram / KIBIBYTES;
        domain.vcpu = resources.n_cpus;
        domain.set_virt_type (DomainVirtType.KVM);

        set_os_config (domain, install_media);

        domain.set_features ({ "acpi", "apic", "pae" });
        var clock = new DomainClock ();
        if (install_media.os != null && install_media.os.short_id.contains ("win"))
            clock.set_offset (DomainClockOffset.LOCALTIME);
        else
            clock.set_offset (DomainClockOffset.UTC);
        domain.set_clock (clock);

        set_target_media_config (domain, target_path);
        set_unattended_floppy_config (domain, install_media);
        set_source_media_config (domain, install_media);

        var input = new DomainInput ();
        input.set_bus (DomainInputBus.USB);
        input.set_device_type (DomainInputDeviceType.TABLET);
        domain.add_device (input);

        var graphics = new DomainGraphicsSpice ();
        graphics.set_autoport (true);
        domain.add_device (graphics);

        set_video_config (domain, install_media);

        domain.set_lifecycle (DomainLifecycleEvent.ON_POWEROFF, DomainLifecycleAction.DESTROY);
        domain.set_lifecycle (DomainLifecycleEvent.ON_REBOOT, DomainLifecycleAction.DESTROY);
        domain.set_lifecycle (DomainLifecycleEvent.ON_CRASH, DomainLifecycleAction.DESTROY);

        var console = new DomainConsole ();
        console.set_source (new DomainChardevSourcePty ());
        domain.add_device (console);

        var iface = new DomainInterfaceUser ();
        domain.add_device (iface);

        var sound = new DomainSound ();
        sound.set_model (DomainSoundModel.AC97);
        domain.add_device (sound);

        return domain;
    }

    public void post_install_setup (Domain domain) {
        set_os_config (domain);
        domain.set_lifecycle (DomainLifecycleEvent.ON_REBOOT, DomainLifecycleAction.RESTART);
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
        var pool_path = get_pkgconfig ("images");
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

    private void set_target_media_config (Domain domain, string target_path) {
        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_guest_device_type (DomainDiskGuestDeviceType.DISK);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("qcow2");
        disk.set_source (target_path);
        disk.set_target_dev ("hda");
        disk.set_target_bus (DomainDiskBus.IDE);

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

        if (install_media.from_image)
            disk.set_type (DomainDiskType.FILE);
        else
            disk.set_type (DomainDiskType.BLOCK);

        domain.add_device (disk);
    }

    private void set_unattended_floppy_config (Domain domain, InstallerMedia install_media) {
        if (!(install_media is UnattendedInstaller))
            return;

        var floppy_path = (install_media as UnattendedInstaller).floppy_path;
        if (floppy_path == null)
            return;

        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_guest_device_type (DomainDiskGuestDeviceType.FLOPPY);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("raw");
        disk.set_source (floppy_path);
        disk.set_target_dev ("fd");

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

        var unattended = install_media as UnattendedInstaller;

        var kernel_path = unattended.kernel_path;
        var initrd_path = unattended.initrd_path;

        if (kernel_path == null || initrd_path == null)
            return;

        os.set_kernel (kernel_path);
        os.set_ramdisk (initrd_path);
        os.set_cmdline ("ks=floppy");
    }

    private void set_video_config (Domain domain, InstallerMedia install_media) {
        var video = new DomainVideo ();

        // FIXME: Should be QXL for every OS. Work-around for a Qemu bug
        if (install_media is Win7Installer)
            video.set_model (DomainVideoModel.VGA);
        else
            video.set_model (DomainVideoModel.QXL);

        domain.add_device (video);
    }

    private StoragePermissions get_default_permissions () {
        var permissions = new StoragePermissions ();

        permissions.set_owner ((uint) Posix.getuid ());
        permissions.set_group ((uint) Posix.getgid ());
        permissions.set_mode (744);

        return permissions;
    }
}
