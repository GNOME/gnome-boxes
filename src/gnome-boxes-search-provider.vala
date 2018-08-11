// This file is part of GNOME Boxes. License: LGPLv2+

[DBus (name = "org.gnome.Shell.SearchProvider2")]
public class Boxes.SearchProvider: Object {
    private SearchProviderApp app;
    private bool loading;
    public bool loaded { get; set; }
    private HashTable<string, BoxConfig> boxes;
    private uint next_id;

    public SearchProvider (SearchProviderApp app) {
        this.app = app;
        boxes = new HashTable<string, BoxConfig> (str_hash, str_equal);
    }

    private void add_box (BoxConfig box) {
        var id = next_id++.to_string ();
        box.set_data ("search-id", id);

        boxes.insert (id, box);
    }

    private async void load () {
        // avoid reentering load () from a different request
        while (!loaded && loading) {
            var wait = notify["loaded"].connect (() => {
                load.callback ();
            });

            yield;

            disconnect (wait);
            if (loaded)
                return;
        }

        loading = true;
        var dir = File.new_for_path (get_user_pkgconfig_source ());
        yield foreach_filename_from_dir (dir, (filename) => {
            var source = new CollectionSource.with_file (filename);
            if (!source.enabled)
                return false;

            foreach (var group in source.get_groups ("display")) {
                var box = new BoxConfig.with_group (source, group);
                add_box (box);
            }

            return false;
        });

        loaded = true;
        loading = false;
    }

    private async string[] search (owned string[] terms) {
        app.hold ();
        string[] normalized_terms = canonicalize_for_search (string.joinv(" ", terms)).split(" ");
        var matches = new GenericArray<BoxConfig> ();

        debug ("search (%s)", string.joinv (", ", terms));
        if (!loaded)
            yield load ();

        foreach (var box in boxes.get_values ()) {
            if (box.contains_strings (normalized_terms))
                matches.add (box);
        }

        matches.sort( (a, b) => { return a.compare (b); });
        var results = new string[matches.length];
        for (int i = 0; i < matches.length; i++)
            results[i] = matches[i].get_data ("search-id");

        app.release ();
        return results;
    }

    public async string[] GetInitialResultSet (string[] terms) throws GLib.Error {
        return yield search (terms);
    }

    public async string[] GetSubsearchResultSet (string[] previous_results,
                                           string[] new_terms) throws GLib.Error {
        return yield search (new_terms);
    }

    public async HashTable<string, Variant>[] get_metas (owned string[] ids) throws GLib.Error {
        var metas = new HashTable<string, Variant>[ids.length];
        app.hold ();

        debug ("GetResultMetas (%s)", string.joinv (", ", ids));
        uint n = 0;
        foreach (var id in ids) {
            var box = boxes.lookup (id);
            if (box == null)
                continue;

            var meta = new HashTable<string, Variant> (str_hash, str_equal);
            metas[n] = meta;
            n++;

            meta.insert ("id", new Variant.string (id));
            meta.insert ("name", new Variant.string (box.last_seen_name));

            var file = File.new_for_path (Boxes.get_screenshot_filename (box.uuid));
            FileInfo? info = null;
            try {
                info = yield file.query_info_async (FileAttribute.STANDARD_TYPE, FileQueryInfoFlags.NONE);
            } catch (GLib.Error error) { }

            if (info != null) {
                var icon = new FileIcon (file);
                meta.insert ("gicon", new Variant.string (icon.to_string ()));
            } else {
                meta.insert ("gicon", new Variant.string (new ThemedIcon ("gnome-boxes").to_string ()));
            }
        }

        app.release ();
        return metas[0:n];
    }

    /* We have to put this in a separate method because vala does not seem to honor "owned"
       in the dbus method handler. I.e. it doesn't copy the ids array. */
    public async HashTable<string, Variant>[] GetResultMetas (string[] ids) throws GLib.Error {
        return yield get_metas (ids);
    }

    public void ActivateResult (string search_id, string[] terms, uint32 timestamp) throws GLib.Error {
        app.hold ();

        debug ("ActivateResult (%s)", search_id);

        var box = boxes.lookup (search_id);
        if (box == null) {
            warning ("Can't find id: " + search_id);
            app.release ();
            return;
        }

        string uuid = box.uuid;
        try {
            var cmd = "gnome-boxes --open-uuid " + uuid;
            if (!Process.spawn_command_line_async (cmd))
                stderr.printf ("Failed to launch Boxes with uuid '%s'\n", uuid);
        } catch (SpawnError error) {
            stderr.printf ("Failed to launch Boxes with uuid '%s'\n", uuid);
            warning (error.message);
        }

        app.release ();
    }

    public void LaunchSearch (string[] terms, uint32 timestamp) throws GLib.Error {
        app.hold ();

        debug ("LaunchSearch (%s)", string.joinv (", ", terms));

        try {
            string[] args = {};
            args += "gnome-boxes";
            foreach (var term in terms) {
                args += "--search";
                args += term;
            }
            if (!Process.spawn_async (null, args, null, SpawnFlags.SEARCH_PATH, null, null))
                stderr.printf ("Failed to launch Boxes for search\n");
        } catch (SpawnError error) {
            stderr.printf ("Failed to launch Boxes for search\n");
            warning (error.message);
        }

        app.release ();
    }
}

public class Boxes.SearchProviderApp: GLib.Application {
    public SearchProviderApp () {
        Object (application_id: "org.gnome.Boxes.SearchProvider",
                flags: ApplicationFlags.IS_SERVICE,
                inactivity_timeout: 10000);
    }

    public override bool dbus_register (GLib.DBusConnection connection, string object_path) {
        try {
            connection.register_object (object_path, new SearchProvider (this));
        } catch (IOError error) {
            stderr.printf ("Could not register service: %s", error.message);
            quit ();
        }
        return true;
    }

    public override void startup () {
        if (Environment.get_variable ("BOXES_SEARCH_PROVIDER_PERSIST") != null)
            hold ();
        base.startup ();
    }
}

int main () {
    return new Boxes.SearchProviderApp ().run ();
}
