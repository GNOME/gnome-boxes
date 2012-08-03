// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.DisplayConfig: GLib.Object, Boxes.IConfig {
    private CollectionSource source;

    private bool has_file {
        get { return source.has_file; }
        set { source.has_file = value; }
    }
    private string? filename {
        get { return source.filename; }
        set { warning ("not allowed to change filename"); }
    }
    private KeyFile keyfile {
        get { return source.keyfile; }
    }

    private string group;

    public string[]? categories {
        owned get { return get_string_list (group, "categories"); }
        set { keyfile.set_string_list (group, "categories", value); }
    }

    public DisplayConfig (CollectionSource source, string? subgroup = null) {
        this.source = source;

        this.group = "display";
        if (subgroup != null)
            this.group += " " + subgroup;
    }

    public void add_category (string category) {
        if (category in categories)
            return;

        // FIXME: vala bug if in one line
        string[] categories = categories;
        categories += category;
        this.categories = categories;

        save ();
    }

    public void save_display_property (Object display, string property_name) {
        var value = Value (display.get_class ().find_property (property_name).value_type);

        display.get_property (property_name, ref value);

        if (value.type () == typeof (string))
            keyfile.set_string (group, property_name, value.get_string ());
        else if (value.type () == typeof (uint64))
            keyfile.set_uint64 (group, property_name, value.get_uint64 ());
        else if (value.type () == typeof (int64))
            keyfile.set_int64 (group, property_name, value.get_int64 ());
        else if (value.type () == typeof (bool))
            keyfile.set_boolean (group, property_name, value.get_boolean ());
        else
            warning ("unhandled property %s type, value: %s".printf (
                         property_name, value.strdup_contents ()));

        save ();
    }

    public void load_display_property (Object display, string property_name, Value default_value) {
        var property = display.get_class ().find_property (property_name);
        if (property == null) {
            debug ("You forgot the property '%s' needs to have public getter!", property_name);
        }

        var value = Value (property.value_type);

        try {
            if (value.type () == typeof (string))
                value = keyfile.get_string (group, property_name);
            if (value.type () == typeof (uint64))
                value = keyfile.get_uint64 (group, property_name);
            if (value.type () == typeof (int64))
                value = keyfile.get_int64 (group, property_name);
            if (value.type () == typeof (bool))
                value = keyfile.get_boolean (group, property_name);
        } catch (GLib.Error err) {
            value = default_value;
        }

        display.set_property (property_name, value);
    }
}
