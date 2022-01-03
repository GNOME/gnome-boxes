// This file is part of GNOME Boxes. License: LGPLv2+

public class Boxes.BoxConfig: GLib.Object, Boxes.IConfig {
    public struct SavedProperty {
        string name;
        Value default_value;
    }

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

    public string group { get; private set; }

    public string? last_seen_name {
        owned get { return get_string (group, "last-seen-name"); }
        set { keyfile.set_string (group, "last-seen-name", value); }
    }

    public string? uuid {
        owned get { return get_string (group, "uuid"); }
        set { keyfile.set_string (group, "uuid", value); }
    }

    public string[]? categories {
        owned get { return get_string_list (group, "categories"); }
        set { keyfile.set_string_list (group, "categories", value); }
    }

    public int64 access_last_time { set; get; }
    public int64 access_first_time { set; get; }
    public int64 access_total_time { set; get; } // in seconds
    public int64 access_ntimes { set; get; }
    private SavedProperty[] access_properties;

    construct {
        access_properties = {
            SavedProperty () { name = "access-last-time", default_value = (int64) (-1) },
            SavedProperty () { name = "access-first-time", default_value = (int64) (-1) },
            SavedProperty () { name = "access-total-time", default_value = (int64) (-1) },
            SavedProperty () { name = "access-ntimes", default_value = (uint64) 0 }
        };
    }

    public BoxConfig.with_group (CollectionSource source, string group) {
        this.source = source;

        warn_if_fail (group.has_prefix ("display"));
        this.group = group;

        save_properties (this, access_properties);
    }

    public void delete () {
        try {
            keyfile.remove_group (group);
        } catch (GLib.Error error) {
        }

        save ();
    }

    private void save_property (Object object, string property_name) {
        var value = Value (object.get_class ().find_property (property_name).value_type);

        object.get_property (property_name, ref value);

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

    private ParamSpec? load_property (Object object, string property_name, Value default_value) {
        var property = object.get_class ().find_property (property_name);
        if (property == null) {
            debug ("You forgot the property '%s' needs to have public getter!", property_name);
            return null;
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

        object.set_property (property_name, value);

        return property;
    }

    public void save_properties (Object object, SavedProperty[] properties) {
        foreach (var prop in properties) {
            var property = load_property (object, prop.name, prop.default_value);
            if (property == null)
                return;

            object.notify.connect ((object, pspec) => {
                if (pspec.name == property.name)
                    save_property (object, pspec.name);
           });
        }
    }

    private string? filter_data;

    private void update_filter_data () {
        var builder = new StringBuilder ();

        if (last_seen_name != null) {
            builder.append (canonicalize_for_search (last_seen_name));
            builder.append_unichar (' ');
        }

        // add categories, url? other metadata etc..

        filter_data = builder.str;
    }

    public bool contains_strings (string[] strings) {
        if (filter_data == null)
            update_filter_data ();

        foreach (string i in strings) {
            if (! (i in filter_data))
                return false;
        }
        return true;
    }

    public int compare (BoxConfig other) {
        // sort by last time used
        if (access_last_time > 0 || other.access_last_time > 0) {
            if (access_last_time > other.access_last_time)
                return -1;
            else if (access_last_time < other.access_last_time)
                return 1;
        }

        var name = last_seen_name;
        var other_name = other.last_seen_name;

        // then by name
        if (is_set (name) && is_set (other_name))
            return name.collate (other_name);

        // Sort empty names last
        if (is_set (name))
            return -1;
        if (is_set (other_name))
            return 1;

        return 0;
    }

}
