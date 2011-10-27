// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private abstract class Boxes.Display: GLib.Object, Boxes.IProperties {
    public abstract string protocol { get; }
    public abstract string uri { owned get; }

    public bool need_password { get; set; }
    public bool need_username { get; set; }
    public string? password { get; set; }
    public string? username { get; set; }

    public signal void show (int display_id);
    public signal void hide (int display_id);
    public signal void disconnected ();

    public abstract Gtk.Widget? get_display (int n) throws Boxes.Error;
    public abstract void connect_it ();
    public abstract void disconnect_it ();

    public abstract List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page);

    protected HashTable<int, Gtk.Widget?> displays;
    construct {
        displays = new HashTable<int, Gtk.Widget> (direct_hash, direct_equal);
    }
}
