// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private abstract class Boxes.Display: GLib.Object, Boxes.IProperties {
    protected struct SavedProperty {
        string name;
        Value default_value;
    }

    public abstract string protocol { get; }
    public abstract string uri { owned get; }

    public bool need_password { get; set; }
    public bool need_username { get; set; }
    public string? password { get; set; }
    public string? username { get; set; }

    public signal void show (int display_id);
    public signal void hide (int display_id);
    public signal void disconnected ();

    public abstract Gtk.Widget get_display (int n) throws Boxes.Error;
    public abstract Gdk.Pixbuf? get_pixbuf (int n) throws Boxes.Error;

    public abstract void connect_it ();
    public abstract void disconnect_it ();

    public abstract List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page);

    protected HashTable<int, Gtk.Widget?> displays;
    construct {
        displays = new HashTable<int, Gtk.Widget> (direct_hash, direct_equal);
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
