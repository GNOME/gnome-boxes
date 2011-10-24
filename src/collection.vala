// This file is part of GNOME Boxes. License: LGPLv2+

private abstract class Boxes.CollectionItem: Boxes.UI {
    public string name;
}

private class Boxes.Collection: GLib.Object {
    private Boxes.App app;
    public signal void item_added (CollectionItem item);

    GenericArray<CollectionItem> items;

    construct {
        items = new GenericArray<CollectionItem> ();
    }

    public Collection (Boxes.App app) {
        this.app = app;
    }

    public void add_item (CollectionItem item) {
        items.add (item);
        item_added (item);
    }
}

private class Boxes.CollectionSource: GLib.Object {
    private KeyFile keyfile;
    public string? name {
        owned get { return get_string ("source", "name"); }
        set { keyfile.set_string ("source", "name", value); }
    }
    public string? source_type {
        owned get { return get_string ("source", "type"); }
        set { keyfile.set_string ("source", "type", value); }
    }
    public string? uri {
        owned get { return get_string ("source", "uri"); }
        set { keyfile.set_string ("source", "uri", value); }
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
}

private class Boxes.Category: GLib.Object {
    public string name;

    public Category (string name) {
        this.name = name;
    }
}
