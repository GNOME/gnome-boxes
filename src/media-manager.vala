// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GUdev;

private class Boxes.MediaManager : Object {
    public OSDatabase os_db { get; private set; }
    public Client client { get; private set; }

    public MediaManager () {
        client = new GUdev.Client ({"block"});
        try {
            os_db = new OSDatabase ();
        } catch (GLib.Error error) {
            critical ("Error fetching default OS database: %s", error.message);
        }
    }

    public async InstallerMedia create_installer_media_for_path (string       path,
                                                                 Cancellable? cancellable) throws GLib.Error {
        var media = yield InstallerMedia.create_for_path (path, this, cancellable);

        if (media.os == null)
            return media;

        switch (media.os.short_id) {
        case "fedora14":
        case "fedora15":
        case "fedora16":
            media = new FedoraInstaller.copy (media);

            break;

        case "win7":
        case "win2k8":
            media = new Win7Installer.copy (media);

            break;

        case "winxp":
        case "win2k":
        case "win2k3":
            media = new WinXPInstaller.copy (media);

            break;

        default:
            return media;
        }

        return media;
    }
}
