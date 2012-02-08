// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GUdev;

private class Boxes.MediaManager : Object {
    public OSDatabase os_db { get; private set; }
    public Client client { get; private set; }
    public GLib.List<InstallerMedia> medias { owned get { return media_hash.get_values (); } }

    public signal void media_available (InstallerMedia media);
    public signal void media_unavailable (InstallerMedia media);

    private HashTable<string,InstallerMedia> media_hash;

    public MediaManager () {
        client = new GUdev.Client ({"block"});
        try {
            os_db = new OSDatabase ();
        } catch (GLib.Error error) {
            critical ("Error fetching default OS database: %s", error.message);
        }
        media_hash = new HashTable<string, InstallerMedia> (str_hash, str_equal);
        fetch_installer_medias.begin ();

        client.uevent.connect (on_udev_event);
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

    private async void fetch_installer_medias () {
        var enumerator = new GUdev.Enumerator (client);
        enumerator.add_match_property ("OSINFO_BOOTABLE", "1");

        foreach (var device in enumerator.execute ())
            yield add_device (device);
    }

    private void on_udev_event (Client client, string action, GUdev.Device device) {
        var name = device.get_name ();
        debug ("udev action '%s' for device '%s'", action, name);

        if (action == "remove" || action == "change") {
            var media = media_hash.lookup (name);
            if (media != null) {
                media_hash.remove (name);
                media_unavailable (media);
            }
        }

        if (action == "add" || action == "change" && device.get_property_as_boolean ("OSINFO_BOOTABLE"))
            add_device.begin (device);
    }

    private async void add_device (GUdev.Device device) {
        if (device.get_property ("DEVTYPE") != "disk")
            // We don't want to deal with partitions to avoid duplicate medias
            return;

        var path = device.get_device_file ();
        try {
            var media = yield create_installer_media_for_path (path, null);

            media_hash.insert (device.get_name (), media);
            media_available (media);
        } catch (GLib.Error error) {
            warning ("Failed to get information on device '%s': %s. Ignoring..", path, error.message);
        }
    }
}
