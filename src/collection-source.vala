// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.CollectionSource: GLib.Object {
    private KeyFile keyfile;
    public string? name {
        owned get { return get_string ("source", "name"); }
        set {
            keyfile.set_string ("source", "name", value);
            if (has_file)
                FileUtils.unlink (get_pkgconfig_source (filename));
            _filename = null;
            save ();
        }
    }
    public string? source_type {
        owned get { return get_string ("source", "type"); }
        set { keyfile.set_string ("source", "type", value); }
    }
    public string? uri {
        owned get { return get_string ("source", "uri"); }
        set { keyfile.set_string ("source", "uri", value); }
    }
    public string[]? categories {
        owned get { return get_string_list ("display", "categories"); }
        set { keyfile.set_string_list ("display", "categories", value); }
    }

    private string? _filename;
    public string? filename {
        get {
            if (_filename == null)
                _filename = make_filename (name);
            return _filename;
        }
        set { _filename = value; }
    }

    private bool has_file;

    construct {
        keyfile = new KeyFile ();
    }

    public CollectionSource (string name, string source_type, string uri) {
        this.name = name;
        this.source_type = source_type;
        this.uri = uri;
    }

    public CollectionSource.with_file (string filename) throws GLib.Error {
        this.filename = filename;
        has_file = true;
        load ();
    }

    private void load () throws GLib.Error {
        keyfile.load_from_file (get_pkgconfig_source (filename),
                                KeyFileFlags.KEEP_COMMENTS | KeyFileFlags.KEEP_TRANSLATIONS);
    }

    public void save () {
        keyfile_save (keyfile, get_pkgconfig_source (filename), has_file);
        has_file = true;
    }

    private string? get_string (string group, string key) {
        try {
            return keyfile.get_string (group, key);
        } catch (GLib.KeyFileError error) {
            return null;
        }
    }

    private string[]? get_string_list (string group, string key) {
        try {
            return keyfile.get_string_list (group, key);
        } catch (GLib.KeyFileError error) {
            return null;
        }
    }

    public void save_display_property (Object display, string property_name) {
        var group = "display";
        var value = Value (display.get_class ().find_property (property_name).value_type);

        display.get_property (property_name, ref value);

        if (value.type () == typeof (string))
            keyfile.set_string (group, property_name, value.get_string ());
        else if (value.type () == typeof (bool))
            keyfile.set_boolean (group, property_name, value.get_boolean ());
        else
            warning ("unhandled property %s type, value: %s".printf (
                         property_name, value.strdup_contents ()));

        save ();
    }

    public void load_display_property (Object display, string property_name, Value default_value) {
        var group = "display";
        var value = Value (display.get_class ().find_property (property_name).value_type);

        try {
            if (value.type () == typeof (string))
                value = keyfile.get_string (group, property_name);
            if (value.type () == typeof (bool))
                value = keyfile.get_boolean (group, property_name);
        } catch (GLib.Error err) {
            value = default_value;
        }

        display.set_property (property_name, value);
    }
}
