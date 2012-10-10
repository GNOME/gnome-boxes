// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GUdev;
using Tracker;

private class Boxes.MediaManager : Object {
    private const string SPARQL_QUERY = "SELECT nie:url(?iso) nie:title(?iso) osinfo:id(?iso) osinfo:mediaId(?iso)" +
                                        " { ?iso nfo:isBootable true }";

    public OSDatabase os_db { get; private set; }
    public Client client { get; private set; }

    private Sparql.Connection connection;

    public MediaManager () {
        client = new GUdev.Client ({"block"});
        os_db = new OSDatabase ();
        try {
            os_db.load ();
        } catch (GLib.Error error) {
            critical ("Error fetching default OS database: %s", error.message);
        }
        try {
            connection = Sparql.Connection.get ();
        } catch (GLib.Error error) {
            critical ("Error connecting to Tracker: %s", error.message);
        }
    }

    public async InstallerMedia create_installer_media_for_path (string       path,
                                                                 Cancellable? cancellable) throws GLib.Error {
        var media = yield InstallerMedia.create_for_path (path, this, cancellable);

        return create_installer_media_from_media (media);
    }

    public async GLib.List<InstallerMedia> list_installer_medias () {
        var list = new GLib.List<InstallerMedia> ();

        // First HW media
        var enumerator = new GUdev.Enumerator (client);
        enumerator.add_match_property ("OSINFO_BOOTABLE", "1");

        foreach (var device in enumerator.execute ()) {
            if (device.get_property ("DEVTYPE") != "disk")
                // We don't want to deal with partitions to avoid duplicate medias
                continue;

            var path = device.get_device_file ();
            try {
                var media = yield create_installer_media_for_path (path, null);

                list.append (media);
            } catch (GLib.Error error) {
                warning ("Failed to get information on device '%s': %s. Ignoring..", path, error.message);
            }
        }

        if (connection == null)
            return list;

        // Now ISO files
        try {
            var cursor = yield connection.query_async (SPARQL_QUERY);
            while (yield cursor.next_async ()) {
                var file = File.new_for_uri (cursor.get_string (0));
                var path = file.get_path ();
                if (path == null)
                    continue; // FIXME: Support non-local files as well
                var title = cursor.get_string (1);
                var os_id = cursor.get_string (2);
                var media_id = cursor.get_string (3);

                try {
                    var media = yield create_installer_media_from_iso_info (path, title, os_id, media_id);

                    list.insert_sorted (media, compare_media);
                } catch (GLib.Error error) {
                    warning ("Failed to use ISO '%s': %s", path, error.message);
                }
            }
        } catch (GLib.Error error) {
            warning ("Failed to fetch list of ISOs from Tracker: %s.", error.message);
        }

        return list;
    }

    private static int compare_media (InstallerMedia media_a, InstallerMedia media_b) {
        return strcmp (media_a.label, media_b.label);
    }

    private async InstallerMedia create_installer_media_from_iso_info (string  path,
                                                                       string? label,
                                                                       string? os_id,
                                                                       string? media_id) throws GLib.Error {
        if (label == null || os_id == null || media_id == null)
            return yield create_installer_media_for_path (path, null);

        var os = os_db.get_os_by_id (os_id);
        var os_media = os_db.get_media_by_id (os, media_id);
        var resources = os_db.get_resources_for_os (os, os_media.architecture);
        var media = new InstallerMedia.from_iso_info (path, label, os, os_media, resources);

        return create_installer_media_from_media (media);
    }

    private InstallerMedia create_installer_media_from_media (InstallerMedia media) throws GLib.Error {
        if (media.os == null)
            return media;

        switch (media.os.distro) {
        case "fedora":
            return new FedoraInstaller.from_media (media);

        case "win":
            switch (media.os.short_id) {
            case "win7":
            case "win2k8":
                return new Win7Installer.from_media (media);

            case "winxp":
            case "win2k":
            case "win2k3":
                return new WinXPInstaller.from_media (media);

            default:
                return media;
            }

        default:
            return media;
        }
    }
}
