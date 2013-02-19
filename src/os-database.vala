// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;

public errordomain Boxes.OSDatabaseError {
    NON_BOOTABLE,
    UNKNOWN_OS_ID,
    UNKNOWN_MEDIA_ID
}

private class Boxes.OSDatabase : GLib.Object {
    private const int DEFAULT_VCPUS = 1;
    private const int64 DEFAULT_RAM = 500 * (int64) MEBIBYTES;

    // We use the dynamically growing storage format (qcow2) so actual amount of disk space used is completely
    // dependent on the OS/guest.
    private const int64 DEFAULT_STORAGE = 20 * (int64) GIBIBYTES;

    private Db? db;

    private bool db_loading;

    private signal void db_loaded ();

    private static Resources get_default_resources () {
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
            yield run_in_thread (() => { loader.process_default_path (); });
        } catch (GLib.Error e) {
            warning ("Error loading default libosinfo database: %s", e.message);
        }
        try {
            yield run_in_thread (() => { loader.process_path (get_logos_db ()); }); // Load our custom database
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

        if (db.identify_media (media))
            return media;

        return null;
    }

    public async Os get_os_by_id (string id) throws OSDatabaseError {
        if (!yield ensure_db_loaded ())
            throw new OSDatabaseError.UNKNOWN_OS_ID ("Unknown OS ID '%s'", id);

        var os = db.get_os (id);
        if (os == null)
            throw new OSDatabaseError.UNKNOWN_OS_ID ("Unknown OS ID '%s'", id);

        return os;
    }

    public Media get_media_by_id (Os os, string id) throws OSDatabaseError {
        var medias = os.get_media_list ();

        var media = medias.find_by_id (id) as Media;
        if (media == null)
            throw new OSDatabaseError.UNKNOWN_MEDIA_ID ("Unknown media ID '%s'", id);

        return media;
    }

    public Resources get_resources_for_os (Os? os, string? architecture) {
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

    public Resources? get_recommended_resources_for_os (Os os, string architecture) {
        string[] prefs = { architecture, ARCHITECTURE_ALL };

        var list = os.get_recommended_resources ();

        return get_prefered_resources (list, prefs);
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

    private Resources? get_prefered_resources (ResourcesList list, string[] prefs) {
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

    private ResourcesList filter_resources_list_by_arch (ResourcesList list, string arch) {
        var new_list = new ResourcesList ();
        foreach (var entity in list.get_elements ()) {
            var resources = entity as Resources;
            var compatibility = compare_cpu_architectures (arch, resources.architecture);
            if (compatibility == CPUArchCompatibity.IDENTICAL || compatibility == CPUArchCompatibity.COMPATIBLE)
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
