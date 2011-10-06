// This file is part of GNOME Boxes. License: LGPLv2

private abstract class Boxes.Display: GLib.Object {
    protected HashTable<int, Gtk.Widget?> displays;

    public signal void show (int display_id);
    public signal void hide (int display_id);
    public signal void disconnected ();

    public abstract Gtk.Widget get_display (int n) throws Boxes.Error;
    public abstract void connect_it ();
    public abstract void disconnect_it ();

    public override void constructed () {
        displays = new HashTable<int, Gtk.Widget> (direct_hash, direct_equal);
    }

    ~Boxes () {
        disconnect_it ();
    }
}
