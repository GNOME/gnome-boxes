// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using Tracker;

private class Boxes.MediaManager : Object {
    private static MediaManager media_manager;

    public OSDatabase os_db { get; private set; }
#if !FLATPAK
    public GUdev.Client client { get; private set; }
#endif

    public delegate void InstallerRecognized (Osinfo.Media os_media, Osinfo.Os os);

    private Sparql.Connection connection;

    public static MediaManager get_instance () {
        if (media_manager == null)
            media_manager = new MediaManager ();

        return media_manager;
    }

    public async InstallerMedia create_installer_media_for_path (string       path,
                                                                 Cancellable? cancellable = null) throws GLib.Error {
        InstallerMedia media;

        try {
            media = yield new InstalledMedia.guess_os (path, this);
        } catch (IOError.NOT_SUPPORTED e) {
            media = yield new InstallerMedia.for_path (path, this, cancellable);
        }

        return create_installer_media_from_media (media);
    }

    public async InstallerMedia? create_installer_media_from_config (GVirConfig.Domain config) {
        var path = VMConfigurator.get_source_media_path (config);
        if (path == null)
            return null;

        try {
            if (VMConfigurator.is_import_config (config))
                return yield new InstalledMedia.guess_os (path, this);
            else if (VMConfigurator.is_libvirt_system_import_config (config))
                return new LibvirtMedia (path, config);
            else if (VMConfigurator.is_libvirt_cloning_config (config))
                return new LibvirtClonedMedia (path, config);
        } catch (GLib.Error error) {
                debug ("%s", error.message);

                return null;
        }

        var label = config.title;

        Os? os = null;
        Media? os_media = null;

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
            media = create_installer_media_from_media (media);
        } catch (GLib.Error error) {
            debug ("%s", error.message); // We just failed to create more specific media instance, no biggie!
        }

        return media;
    }

    public async GLib.List<InstallerMedia> list_installer_medias () {
        var list = new GLib.List<InstallerMedia> ();

#if !FLATPAK
        // First HW media
        var enumerator = new GUdev.Enumerator (client);
        // We don't want to deal with partitions to avoid duplicate medias
        enumerator.add_match_property ("DEVTYPE", "disk");

        foreach (var device in enumerator.execute ()) {
            if (device.get_property ("ID_FS_BOOT_SYSTEM_ID") == null &&
                !device.get_property_as_boolean ("OSINFO_BOOTABLE"))
                continue;

            var path = device.get_device_file ();
            var file = File.new_for_path (path);
            try {
                var info = yield file.query_info_async (FileAttribute.ACCESS_CAN_READ,
                                                        FileQueryInfoFlags.NONE,
                                                        Priority.DEFAULT,
                                                        null);
                if (!info.get_attribute_boolean (FileAttribute.ACCESS_CAN_READ)) {
                    debug ("No read access to '%s', ignoring..", path);
                    continue;
                }

                var media = yield create_installer_media_for_path (path);

                list.append (media);
            } catch (GLib.Error error) {
                warning ("Failed to get information on device '%s': %s. Ignoring..", path, error.message);
            }
        }
#endif

        if (connection == null)
            return list;

        // Now ISO files
        try {
            var query = yield new TrackerISOQuery (connection);
            string path, title, os_id, media_id;
            string[] lang_list;

            while (yield query.fetch_next_iso_data (out path,
                                                    out title,
                                                    out os_id,
                                                    out media_id,
                                                    out lang_list)) {
                try {
                    var media = yield create_installer_media_from_iso_info (path, title, os_id, media_id, lang_list);
                    unowned GLib.List<InstallerMedia> dup_node = list.find_custom (media, compare_media_by_label);
                    if (dup_node != null) {
                        // In case of duplicate media, prefer:
                        // * released OS over unreleased one
                        // * latest release
                        // * soft over hard media
                        var dup_media = dup_node.data;
                        if (compare_media_by_release_date (media, dup_media) <= 0)
                            list.remove (dup_media);
                        else
                            continue;
                    }

                    list.insert_sorted (media, compare_media_by_vendor);
                } catch (GLib.Error error) {
                    warning ("Failed to use ISO '%s': %s", path, error.message);
                }
            }
        } catch (GLib.Error error) {
            warning ("Failed to fetch list of ISOs from Tracker: %s.", error.message);
        }

        return list;
    }

    private static InstallerMedia create_unattended_installer (InstallerMedia media) throws GLib.Error {
        InstallerMedia install_media = media;

        var filter = new Filter ();
        filter.add_constraint (INSTALL_SCRIPT_PROP_PROFILE, INSTALL_SCRIPT_PROFILE_DESKTOP);

        // In case scripts are set as part of the media, let's use them as this
        // info is more accurate than having the scripts set as part of the OS.
        var install_scripts = media.os_media.get_install_script_list ();
        if (install_scripts.get_length () > 0) {

            // Find out whether the media supports a script for DESKTOP profile
            install_scripts = (install_scripts as Osinfo.List).new_filtered (filter) as InstallScriptList;

            if (install_scripts.get_length () > 0) {
                try {
                    install_media = new UnattendedInstaller.from_media (media, install_scripts);
                } catch (GLib.IOError.NOT_SUPPORTED e) {
                    debug ("Unattended installer setup failed: %s", e.message);
                }
            }

            return install_media;
        }

        // In case scripts are not set as part of the media, let's use the ones
        // set as part of the OS.
        install_scripts = media.os.get_install_script_list ();
        install_scripts = (install_scripts as Osinfo.List).new_filtered (filter) as InstallScriptList;
        if (install_scripts.get_length () > 0) {
            try {
                install_media = new UnattendedInstaller.from_media (media, install_scripts);
            } catch (GLib.IOError.NOT_SUPPORTED e) {
                debug ("Unattended installer setup failed: %s", e.message);
            }
        }

        return install_media;
    }

    public InstallerMedia create_installer_media_from_media (InstallerMedia media) throws GLib.Error {
        if (media.os == null)
            return media;

        if (!media.os_media.supports_installer_script ())
            return media;

        return create_unattended_installer (media);
    }

    private MediaManager () {
#if !FLATPAK
        client = new GUdev.Client ({"block"});
#endif
        os_db = new OSDatabase ();
        os_db.load.begin ();
        try {
            connection = Sparql.Connection.get ();
        } catch (GLib.Error error) {
            critical ("Error connecting to Tracker: %s", error.message);
        }
    }

    private static int compare_media_by_label (InstallerMedia media_a, InstallerMedia media_b) {
        return strcmp (media_a.label, media_b.label);
    }

    private static int compare_media_by_release_date (InstallerMedia media_a, InstallerMedia media_b) {
        if (media_a.os == null) {
            if (media_b.os == null)
                return 0;
            else
                return -1;
        } else if (media_b.os == null)
            return 1;
        else {
            var release_a = media_a.os.get_release_date ();
            var release_b = media_b.os.get_release_date ();

            if (release_a == null) {
                if (release_b == null)
                    return 0;
                else
                    return -1;
            } else if (release_b == null)
                return 1;
            else
                return -release_a.compare (release_b);
        }
    }

    private static int compare_media_by_vendor (InstallerMedia media_a, InstallerMedia media_b) {
        if (media_a.os == null) {
            if (media_b.os == null)
                return 0;
            else
                return 1;
        } else if (media_b.os == null)
            return -1;
        else {
            var vendor_comparison = strcmp (media_a.os.get_vendor (), media_b.os.get_vendor ());

            if (vendor_comparison == 0)
                // Within each vendor, list latest release date first
                return compare_media_by_release_date (media_a, media_b);
            else
                return vendor_comparison;
        }
    }

    private async InstallerMedia create_installer_media_from_iso_info (string   path,
                                                                       string?  label,
                                                                       string?  os_id,
                                                                       string?  media_id,
                                                                       string[] lang_list)
                                                                       throws GLib.Error {
        if (!FileUtils.test (path, FileTest.EXISTS))
            throw new Boxes.Error.INVALID (_("No such file %s").printf (path));

        if (label == null || os_id == null || media_id == null || lang_list == null)
            return yield create_installer_media_for_path (path);

        var os = yield os_db.get_os_by_id (os_id);
        var os_media = os_db.get_media_by_id (os, media_id);
        foreach (var lang in lang_list)
            os_media.add_param (Osinfo.MEDIA_PROP_LANG, lang);
        var resources = os_db.get_resources_for_os (os, os_media.architecture);
        var media = new InstallerMedia.from_iso_info (path, label, os, os_media, resources);

        return create_installer_media_from_media (media);
    }
}
