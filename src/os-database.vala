// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;

public errordomain Boxes.OSDatabaseError {
    NON_BOOTABLE,
    UNKNOWN_OS_ID
}

private class Boxes.OSDatabase {
    private const int DEFAULT_VCPUS = 1;
    private const int64 DEFAULT_RAM = 500 * (int64) MEBIBYTES;
    private const int64 DEFAULT_STORAGE = 2 * (int64) GIBIBYTES;

    private Db db;

    private static Resources get_default_resources () {
        var resources = new Resources ("whatever", "x86_64");

        resources.n_cpus = DEFAULT_VCPUS;
        resources.ram = DEFAULT_RAM;
        resources.storage = DEFAULT_STORAGE;

        return resources;
    }

    public OSDatabase () throws GLib.Error {
        var loader = new Loader ();
        loader.process_default_path ();
        db = loader.get_db ();
    }

    public async Os? guess_os_from_install_media (string media_path, Cancellable? cancellable) throws GLib.Error {
        var media = yield Media.create_from_location_async (media_path, Priority.DEFAULT, cancellable);

        return db.guess_os_from_media (media);
    }

    public Os? get_os_by_id (string id) {
        return db.get_os (id);
    }

    public Resources get_resources_for_os (Os? os) {
        if (os == null)
            return get_default_resources ();

        // First try recommended resources
        var list = os.get_recommended_resources ();
        var recommended = get_prefered_resources (list);

        list = os.get_minimum_resources ();
        var minimum = get_prefered_resources (list);

        return get_resources_from_os_resources (minimum, recommended);
    }

    public Media? get_prefered_media_for_os (Os os) {
        var medias = os.get_media_list ();

        return get_prefered_media (medias);
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

    private Resources? get_prefered_resources (ResourcesList list) {
        // Prefer x86_64 resources
        string[] prefs = {"x86_64", "i386", ARCHITECTURE_ALL};

        return get_prefered_entity (list.new_filtered, RESOURCES_PROP_ARCHITECTURE, prefs) as Resources;
    }

    private Media? get_prefered_media (MediaList list) {
        // Prefer x86_64 resources
        string[] prefs = {"x86_64", "i386", ARCHITECTURE_ALL};

        return get_prefered_entity (list.new_filtered, MEDIA_PROP_ARCHITECTURE, prefs) as Media;
    }

    private Entity? get_prefered_entity (ListFilterFunc filter_func, string property, string[] prefs) {
        if (prefs.length <= 0)
            return null;

        var filter = new Filter ();
        filter.add_constraint (property, prefs[0]);
        var filtered = filter_func (filter);
        if (filtered.get_length () <= 0)
            return get_prefered_entity (filter_func, property, prefs[1:prefs.length]);
        else
            // Assumption: There is only one resources instance of each type
            // (minimum/recommended) of each architecture for each OS.
            return filtered.get_nth (0);
    }

    private delegate Osinfo.List ListFilterFunc (Filter filter);
}
