// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;

public errordomain Boxes.OSDatabaseError {
    NON_BOOTABLE,
    DB_LOADING_FAILED,
    UNKNOWN_OS_ID,
    UNKNOWN_MEDIA_ID
}

private class Boxes.OSDatabase : GLib.Object {
    public enum MediaURLsColumns {
        URL = 0,  // string
        OS = 1,   // Osinfo.Os

        LAST
    }

    private const int64 MINIMAL_STORAGE = 10 * (int64) GIBIBYTES;

    private const int DEFAULT_VCPUS = 1;
    private const int64 DEFAULT_RAM = 2 * (int64) GIBIBYTES;

    // We use the dynamically growing storage format (qcow2) so actual amount of disk space used is completely
    // dependent on the OS/guest.
    private const int64 DEFAULT_STORAGE = 30 * (int64) GIBIBYTES;

    private Db? db;

    private bool db_loading;

    private signal void db_loaded ();

    public static Resources get_default_resources () {
        var resources = new Resources ("whatever", "x86_64");

        resources.n_cpus = DEFAULT_VCPUS;
        resources.ram = DEFAULT_RAM;
        resources.storage = DEFAULT_STORAGE;

        return resources;
    }

    public async void load () {
        db_loading = true;
        var loader = new Loader ();
        try {
            yield App.app.async_launcher.launch (() => { loader.process_default_path (); });
        } catch (GLib.Error e) {
            warning ("Error loading default libosinfo database: %s", e.message);
        }
        try {
            yield App.app.async_launcher.launch (() => { loader.process_path (get_custom_osinfo_db ()); }); // Load our custom database
        } catch (GLib.Error e) {
            warning ("Error loading GNOME Boxes libosinfo database: %s", e.message);
        }
        db = loader.get_db ();
        db_loading = false;
        db_loaded ();
    }

    public async Media? guess_os_from_install_media_path (string       media_path,
                                                          Cancellable? cancellable) throws GLib.Error {
        if (!yield ensure_db_loaded ())
            return null;

        var media = yield Media.create_from_location_async (media_path, Priority.DEFAULT, cancellable);

        return yield guess_os_from_install_media (media);
    }

    public async Media? guess_os_from_install_media (Media media) throws GLib.Error {
        if (!yield ensure_db_loaded ())
            return null;

        if (db.identify_media (media))
            return media;

        return null;
    }

    public async Os get_os_by_id (string id) throws OSDatabaseError {
        if (!yield ensure_db_loaded ())
            throw new OSDatabaseError.DB_LOADING_FAILED ("Failed to load OS database");

        var os = db.get_os (id);
        if (os == null)
            throw new OSDatabaseError.UNKNOWN_OS_ID ("Unknown OS ID '%s'", id);

        return os;
    }

    public async GLib.List<weak Osinfo.Entity> get_all_oses_sorted_by_release_date () throws OSDatabaseError {
        if (!yield ensure_db_loaded ())
            throw new OSDatabaseError.DB_LOADING_FAILED ("Failed to load OS database");

        var os_list = db.get_os_list ().get_elements ();
        os_list.sort ((entity_a, entity_b) => {
            var os_a = entity_a as Os;
            var os_b = entity_b as Os;

            if (os_a == null)
                return -1;
            if (os_b == null)
                return 1;

            var release_a = os_a.get_release_date ();
            var release_b = os_b.get_release_date ();

            if (release_a == null)
                return -1;
            else if (release_b == null)
                return 1;

            return release_b.compare (release_a);
        });

        return os_list;
    }

    private const string[] skipped_os_versions = {
        "unknown",
        "rawhide",
        "Rawhide",
        "testing",
        "factory",
    };
    public async Osinfo.Os? get_latest_release_for_os_prefix (string os_id_prefix) {
        Osinfo.Os? latest_version = null;

        var os_list = db.get_os_list ().get_elements ();
        foreach (var entity in os_list) {
            Osinfo.Os os = entity as Osinfo.Os;
            if (!os.id.has_prefix (os_id_prefix))
                continue;

            if (os.get_release_status () != ReleaseStatus.RELEASED &&
                os.get_release_status () != ReleaseStatus.ROLLING)
                continue;

            if (os.version in skipped_os_versions)
                continue;

            if (latest_version == null) {
                latest_version = os;

                continue;
            }

            if (double.parse (os.version) > double.parse (latest_version.version)) {
                latest_version = os;
            }
        }

        return latest_version;
    }

    public async GLib.List<Osinfo.Media> list_downloadable_oses () throws OSDatabaseError {
        if (!yield ensure_db_loaded ())
            throw new OSDatabaseError.DB_LOADING_FAILED ("Failed to load OS database");

        int year, month, day;
        var date_time = new DateTime.now_local ();
        date_time.get_ymd (out year, out month, out day);
        var now = Date ();
        now.set_dmy ((DateDay) day, month, (DateYear) year);

        var after_list = new GLib.List<Osinfo.Media> ();
        foreach (var entity in db.get_os_list ().get_elements ()) {
            var os = entity as Os;

            if (os.get_release_status () != ReleaseStatus.RELEASED &&
                os.get_release_status () != ReleaseStatus.ROLLING)
                continue;

            foreach (var media_entity in os.get_media_list ().get_elements ()) {
                var media = media_entity as Media;

                if (media.url == null)
                    continue;

                if (!(media.architecture in InstalledMedia.supported_architectures))
                    continue;

                var product = os as Product;
                var eol = product.get_eol_date ();
                if (eol == null || now.compare (eol) < 1)
                    after_list.append (media);
            }
        }

        // Sort list in desceding order by release date.
        after_list.sort ((media_a, media_b) => {
            var release_a = media_a.os.get_release_date ();
            var release_b = media_b.os.get_release_date ();

            if (release_a == null)
                return -1;
            else if (release_b == null)
                return 1;

            return release_b.compare (release_a);
        });

        return after_list;
    }

    public Media get_media_by_id (Os os, string id) throws OSDatabaseError {
        var medias = os.get_media_list ();

        var media = medias.find_by_id (id) as Media;
        if (media == null)
            throw new OSDatabaseError.UNKNOWN_MEDIA_ID ("Unknown media ID '%s'", id);

        return media;
    }

    public Resources get_resources_for_os (Os? os, string? architecture = null) {
        if (os == null)
            return get_default_resources ();

        // Prefer x86_64 resources by default
        string[] architectures = {"x86_64", "i686", "i386", ARCHITECTURE_ALL};
        string[] prefs;
        if (architecture != null) {
            prefs = new string[0];
            prefs += architecture;

            foreach (var arch in architectures)
                if (arch != architecture)
                    prefs += arch;
        } else
            prefs = architectures;

        // First try recommended resources
        var list = os.get_recommended_resources ();
        var recommended = get_prefered_resources (list, prefs);

        list = os.get_minimum_resources ();
        var minimum = get_prefered_resources (list, prefs);

        return get_resources_from_os_resources (minimum, recommended);
    }

    public static Resources? get_recommended_resources_for_os (Os os, string? architecture = null) {
        // Prefer x86_64 resources by default
        if (architecture == null)
            architecture = "x86_64";
        string[] prefs = { architecture, ARCHITECTURE_ALL };

        var list = os.get_recommended_resources ();

        return get_prefered_resources (list, prefs);
    }

    public Datamap? get_datamap (string id) {
        return db.get_datamap (id);
    }

    private Resources get_resources_from_os_resources (Resources? minimum, Resources? recommended) {
        var resources = get_default_resources ();

        // Number of CPUs
        if (recommended != null && recommended.n_cpus > 0)
            resources.n_cpus = recommended.n_cpus;
        else if (minimum != null && minimum.n_cpus > 0)
            resources.n_cpus = int.max (minimum.n_cpus, resources.n_cpus);

        // RAM
        if (recommended != null && recommended.ram > 0)
            resources.ram = recommended.ram;
        else if (minimum != null && minimum.ram > 0)
            resources.ram = int64.max (minimum.ram, resources.ram);

        // Storage
        if (recommended != null && recommended.storage > 0)
            resources.storage = recommended.storage;
        else if (minimum != null && minimum.storage > 0)
            resources.storage = int64.max (minimum.storage * 2, resources.storage);

        return resources;
    }

    private static Resources? get_prefered_resources (ResourcesList list, string[] prefs) {
        if (prefs.length <= 0)
            return null;

        var filtered = filter_resources_list_by_arch (list, prefs[0]);
        if (filtered.get_length () <= 0)
            return get_prefered_resources (list, prefs[1:prefs.length]);
        else
            // Assumption: There is only one resources instance of each type
            // (minimum/recommended) of each architecture for each OS.
            return filtered.get_nth (0) as Resources;
    }

    private static ResourcesList filter_resources_list_by_arch (ResourcesList list, string arch) {
        var new_list = new ResourcesList ();
        foreach (var entity in list.get_elements ()) {
            var resources = entity as Resources;
            var compatibility = compare_cpu_architectures (arch, resources.architecture);
            if (compatibility == CPUArchCompatibility.IDENTICAL || compatibility == CPUArchCompatibility.COMPATIBLE)
                new_list.add (resources);
        }

        return new_list;
    }

    private async bool ensure_db_loaded () {
        if (db != null)
            return true;

        if (db_loading) { // Wait for the DB to load..
            ulong db_loaded_id = 0;

            db_loaded_id = db_loaded.connect (() => {
                ensure_db_loaded.callback ();
                disconnect (db_loaded_id);
            });

            yield;
        }

        return (db != null);
    }
}
