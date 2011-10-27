// This file is part of GNOME Boxes. License: LGPLv2+

// Automated installer media for Windows XP, 2000 and 2003
private class Boxes.WinXPInstaller: UnattendedInstaller {
    public WinXPInstaller.copy (InstallerMedia media) throws GLib.Error {
        var unattended_source = get_unattended_dir (media.os.short_id + ".sif");
        base.copy (media, unattended_source, "Winnt.sif");
    }
}
