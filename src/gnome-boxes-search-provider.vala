// This file is part of GNOME Boxes. License: LGPLv2+

[DBus (name = "org.gnome.Shell.SearchProvider")]
public class Boxes.SearchProvider: Object {
    SearchProviderApp app;

    public SearchProvider (SearchProviderApp app) {
        this.app = app;
    }

    private string[] search (string[] terms) {
        string[] result = {};
        app.hold ();

        debug ("search (%s)", string.joinv (", ", terms));

        app.release ();
        return result;
    }

    public string[] GetInitialResultSet (string[] terms) {
        return search (terms);
    }

    public string[] GetSubsearchResultSet (string[] previous_results,
                                           string[] new_terms) {
        return search (new_terms);
    }

    public HashTable<string, Variant>[] GetResultMetas (string[] ids) {
        HashTable<string, Variant>[] result = {};
        app.hold ();

        debug ("GetResultMetas (%s)", string.joinv (", ", ids));

        app.release ();
        return result;
    }

    public void ActivateResult (string search_id) {
        app.hold ();

        debug ("ActivateResult (%s)", search_id);

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
