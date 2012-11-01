// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;

public errordomain Boxes.OSDatabaseError {
    NON_BOOTABLE,
    UNKNOWN_OS_ID,
    UNKNOWN_MEDIA_ID
}

private class Boxes.OSDatabase {
    private const int DEFAULT_VCPUS = 1;
    private const int64 DEFAULT_RAM = 500 * (int64) MEBIBYTES;

    // We use the dynamically growing storage format (qcow2) so actual amount of disk space used is completely
    // dependent on the OS/guest.
    private const int64 DEFAULT_STORAGE = 20 * (int64) GIBIBYTES;

    private Db? db;

    private static Resources get_default_resources () {
        var resources = new Resources ("whatever", "x86_64");

        resources.n_cpus = DEFAULT_VCPUS;
        resources.ram = DEFAULT_RAM;
        resources.storage = DEFAULT_STORAGE;

        return resources;
    }

    public void load () {
        var loader = new Loader ();
        try {
            loader.process_default_path ();
        } catch (GLib.Error e) {
            warning ("Error loading default libosinfo database: %s", e.message);
        }
        try {
            loader.process_path (get_logos_db ()); // Load our custom database
        } catch (GLib.Error e) {
            warning ("Error loading GNOME Boxes libosinfo database: %s", e.message);
        }
        db = loader.get_db ();
    }

    public async Os? guess_os_from_install_media (string media_path,
                                                  out Media os_media,
                                                  Cancellable? cancellable) throws GLib.Error {
        os_media = null;

        if (db == null)
            return null;

        var media = yield Media.create_from_location_async (media_path, Priority.DEFAULT, cancellable);

        return db.guess_os_from_media (media, out os_media);
    }

    public Os get_os_by_id (string id) throws OSDatabaseError {
        if (db == null)
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

        var filter = new Filter ();
        filter.add_constraint (RESOURCES_PROP_ARCHITECTURE, prefs[0]);
        var filtered = list.new_filtered (filter);
        if (filtered.get_length () <= 0)
            return get_prefered_resources (list, prefs[1:prefs.length]);
        else
            // Assumption: There is only one resources instance of each type
            // (minimum/recommended) of each architecture for each OS.
            return filtered.get_nth (0) as Resources;
    }
}
