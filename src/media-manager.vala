// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GUdev;
using Tracker;

private class Boxes.MediaManager : Object {
    private static MediaManager media_manager;
    private const string SPARQL_QUERY = "SELECT nie:url(?iso) nie:title(?iso) osinfo:id(?iso) osinfo:mediaId(?iso)" +
                                        " { ?iso nfo:isBootable true }";

    public OSDatabase os_db { get; private set; }
    public Client client { get; private set; }

    public delegate void InstallerRecognized (Osinfo.Media os_media, Osinfo.Os os);

    private Sparql.Connection connection;

    public static MediaManager get_instance () {
        if (media_manager == null)
            media_manager = new MediaManager ();

        return media_manager;
    }

    public async InstallerMedia create_installer_media_for_path
                                (string               path,
                                 InstallerRecognized? on_installer_recognized = null,
                                 ActivityProgress     progress = new ActivityProgress (),
                                 Cancellable?         cancellable = null) throws GLib.Error {
        var media = yield new InstallerMedia.for_path (path, this, cancellable);

        return yield create_installer_media_from_media (media, on_installer_recognized, progress);
    }

    public async InstallerMedia? create_installer_media_from_config (GVirConfig.Domain config) {
        var path = VMConfigurator.get_source_media_path (config);
        var label = config.title;

        Os? os = null;
        Media? os_media = null;

        if (path == null)
            return null;

        try {
            var os_id = VMConfigurator.get_os_id (config);
            if (os_id != null) {
                os = yield os_db.get_os_by_id (os_id);

                var media_id = VMConfigurator.get_os_media_id (config);
                if (media_id != null)
                    os_media = os_db.get_media_by_id (os, media_id);
            }
        } catch (OSDatabaseError error) {
            warning ("%s", error.message);
        }

        var architecture = (os_media != null) ? os_media.architecture : null;
        var resources = os_db.get_resources_for_os (os, architecture);

        var media = new InstallerMedia.from_iso_info (path, label, os, os_media, resources);
        return_val_if_fail (media != null, null);

        try {
            media = yield create_installer_media_from_media (media);
        } catch (GLib.Error error) {
            debug ("%s", error.message); // We just failed to create more specific media instance, no biggie!
        }

        return media;
    }

    public async GLib.List<InstallerMedia> list_installer_medias () {
        var list = new GLib.List<InstallerMedia> ();

        // First HW media
        var enumerator = new GUdev.Enumerator (client);
        // We don't want to deal with partitions to avoid duplicate medias
        enumerator.add_match_property ("DEVTYPE", "disk");

        foreach (var device in enumerator.execute ()) {
            if (device.get_property ("ID_FS_BOOT_SYSTEM_ID") == null &&
                !device.get_property_as_boolean ("OSINFO_BOOTABLE"))
                continue;

            var path = device.get_device_file ();
            try {
                var media = yield create_installer_media_for_path (path);

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

    public async InstallerMedia create_installer_media_from_media
                                (InstallerMedia       media,
                                 InstallerRecognized? on_installer_recognized = null,
                                 ActivityProgress     progress = new ActivityProgress (),
                                 Cancellable?         cancellable = null) throws GLib.Error {
        if (media.os == null)
            return media;

        if (on_installer_recognized != null)
            on_installer_recognized (media.os_media, media.os);

        progress.progress = 0.5;

        var install_scripts = media.os.get_install_script_list ();
        var filter = new Filter ();
        filter.add_constraint (INSTALL_SCRIPT_PROP_PROFILE, INSTALL_SCRIPT_PROFILE_DESKTOP);
        install_scripts = (install_scripts as Osinfo.List).new_filtered (filter) as InstallScriptList;

        InstallerMedia install_media;
        if (install_scripts.get_length () > 0) {
            var unattended_progress = progress.add_child_activity (0.5);
            unattended_progress.bind_property ("info", progress, "info");

            install_media = yield new UnattendedInstaller.from_media (media, install_scripts, unattended_progress);
        } else
            install_media = media;

        progress.progress = 1.0;

        return install_media;
    }

    private MediaManager () {
        client = new GUdev.Client ({"block"});
        os_db = new OSDatabase ();
        os_db.load.begin ();
        try {
            connection = Sparql.Connection.get ();
        } catch (GLib.Error error) {
            critical ("Error connecting to Tracker: %s", error.message);
        }
    }

    private static int compare_media (InstallerMedia media_a, InstallerMedia media_b) {
        return strcmp (media_a.label, media_b.label);
    }

    private async InstallerMedia create_installer_media_from_iso_info (string  path,
                                                                       string? label,
                                                                       string? os_id,
                                                                       string? media_id) throws GLib.Error {
        if (!FileUtils.test (path, FileTest.EXISTS))
            throw new Boxes.Error.INVALID (_("No such file %s").printf (path));

        if (label == null || os_id == null || media_id == null)
            return yield create_installer_media_for_path (path);

        var os = yield os_db.get_os_by_id (os_id);
        var os_media = os_db.get_media_by_id (os, media_id);
        var resources = os_db.get_resources_for_os (os, os_media.architecture);
        var media = new InstallerMedia.from_iso_info (path, label, os, os_media, resources);

        return yield create_installer_media_from_media (media);
    }
}
