// This file is part of GNOME Boxes. License: LGPLv2+

using GVirConfig;

// Automated installer media for Windows.
private abstract class Boxes.WindowsInstaller: UnattendedInstaller {
    protected override DomainDisk? get_unattended_disk_config () {
        var disk = base.get_unattended_disk_config ();
        if (disk == null)
            return null;

        disk.set_guest_device_type (DomainDiskGuestDeviceType.FLOPPY);
        disk.set_target_dev ("fd");

        return disk;
    }

    public override void setup_domain_config (Domain domain) {
        base.setup_domain_config (domain);
        if (extra_iso != null)
            add_extra_iso (domain);
    }
}
