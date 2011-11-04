// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gtk;

private class Boxes.Selectionbar: GLib.Object {
    public Clutter.Actor actor { get { return gtk_actor; } }
    public static const float spacing = 60.0f;

    private App app;
    private GtkClutter.Actor gtk_actor;
    private Gtk.Toolbar toolbar;
    private Gtk.ToggleToolButton favorite_btn;
    private Gtk.ToggleToolButton remove_btn;

    public Selectionbar (App app) {
        this.app = app;

        toolbar = new Gtk.Toolbar ();
        toolbar.show_arrow = false;
        toolbar.icon_size = Gtk.IconSize.LARGE_TOOLBAR;

        gtk_actor = new GtkClutter.Actor.with_contents (toolbar);
        gtk_actor.opacity = 0;
        gtk_actor.get_widget ().get_style_context ().add_class ("osd");

        favorite_btn = new Gtk.ToggleToolButton ();
        toolbar.insert (favorite_btn, 0);
        favorite_btn.icon_name = "emblem-favorite-symbolic";
        favorite_btn.clicked.connect (() => {
            message ("fixme");
        });

        var separator = new Gtk.SeparatorToolItem();
        toolbar.insert(separator, 1);

        remove_btn = new Gtk.ToggleToolButton ();
        toolbar.insert (remove_btn, 2);
        remove_btn.icon_name = "edit-delete-symbolic";
        remove_btn.clicked.connect (() => {
            message ("fixme");
        });
        toolbar.show_all ();

        actor.reactive = true;
        actor.hide ();

        app.stage.add (actor);
    }
}
