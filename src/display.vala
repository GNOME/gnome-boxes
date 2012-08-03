// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

// too bad we can't make it just a mixin
private abstract class Boxes.DisplayProperties: GLib.Object, Boxes.IPropertiesProvider {
    protected struct SavedProperty {
        string name;
        Value default_value;
    }

    public abstract List<Boxes.Property> get_properties (Boxes.PropertiesPage page);

    private int64 started_time;
    protected void access_start () {
        if (started_time != 0)
            return;

        started_time = get_monotonic_time ();
        access_last_time = get_real_time ();
        access_ntimes += 1;

        if (access_first_time == 0)
            access_first_time = access_last_time;
    }

    protected void access_finish () {
        if (started_time == 0)
            return;

        var duration = get_monotonic_time () - started_time;
        duration /= 1000000; // convert to seconds
        access_total_time += duration;

        started_time = 0;
    }


    public int64 access_last_time { set; get; }
    public int64 access_first_time { set; get; }
    public int64 access_total_time { set; get; } // in seconds
    public int64 access_ntimes { set; get; }
    private SavedProperty[] access_saved_properties;

    construct {
        access_saved_properties = {
            SavedProperty () { name = "access-last-time", default_value = (int64)(-1) },
            SavedProperty () { name = "access-first-time", default_value = (int64)(-1) },
            SavedProperty () { name = "access-total-time", default_value = (int64)(-1) },
            SavedProperty () { name = "access-ntimes", default_value = (uint64)0 }
        };

        this.notify["config"].connect (() => {
            sync_config_with_display (this, access_saved_properties);
        });
    }

    ~DisplayProperties () {
        access_finish ();
    }

    public DisplayConfig? config { get; set; }

    public void sync_config_with_display (Object display, SavedProperty[] saved_properties) {
        if (config == null)
            return;

        foreach (var prop in saved_properties)
            config.load_display_property (display, prop.name, prop.default_value);

        display.notify.connect ((pspec) => {
            foreach (var prop in saved_properties)
                if (pspec.name == prop.name) {
                    config.save_display_property (display, pspec.name);
                    break;
                }
        });
    }
}

private abstract class Boxes.Display: Boxes.DisplayProperties {
    public abstract string protocol { get; }
    public abstract string uri { owned get; }

    public bool can_grab_mouse { get; protected set; }
    public bool mouse_grabbed { get; protected set; }
    public bool need_password { get; protected set; }
    public bool need_username { get; protected set; }
    public string? password { get; set; }
    public string? username { get; set; }

    public signal void show (int display_id);
    public signal void hide (int display_id);
    public signal void disconnected ();

    public abstract Gtk.Widget get_display (int n) throws Boxes.Error;
    public abstract Gdk.Pixbuf? get_pixbuf (int n) throws Boxes.Error;
    public abstract void set_enable_inputs (Gtk.Widget widget, bool enable);

    public abstract void connect_it ();
    public abstract void disconnect_it ();

    protected HashTable<int, Gtk.Widget?> displays;

    construct {
        displays = new HashTable<int, Gtk.Widget> (direct_hash, direct_equal);
    }
}
