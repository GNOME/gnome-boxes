// This file is part of GNOME Boxes. License: LGPLv2+

// Automated installer media for Windows 7 and 2008
private class Boxes.Win7Installer: UnattendedInstaller {
    public Win7Installer.copy (InstallerMedia media) throws GLib.Error {
        var unattended_source = get_unattended_dir (media.os.short_id + ".xml");
        base.copy (media, unattended_source, "Autounattend.xml");
    }
}
