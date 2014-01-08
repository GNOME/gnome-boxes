// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;
using Clutter;

private enum Boxes.SidebarPage {
    COLLECTION,
    WIZARD,
    PROPERTIES,
}

private class Boxes.Sidebar: GLib.Object, Boxes.UI {
    public Clutter.Actor actor { get { return gtk_actor; } }
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }
    public Notebook notebook;
    private uint width;

    private GtkClutter.Actor gtk_actor; // the sidebar box

    public Sidebar () {
        width = 200;

        notify["ui-state"].connect (ui_state_changed);
        setup_sidebar ();
    }

    private void ui_state_changed () {
        switch (ui_state) {
        case UIState.WIZARD:
        case UIState.PROPERTIES:
            App.app.sidebar_revealer.reveal ();
            notebook.page = ui_state == UIState.WIZARD ? SidebarPage.WIZARD : SidebarPage.PROPERTIES;
            break;

        default:
            App.app.sidebar_revealer.unreveal ();
            break;
        }
    }

    private void setup_sidebar () {
        notebook = new Gtk.Notebook ();
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);
        gtk_actor.get_widget ().get_style_context ().add_class ("boxes-bg");
        gtk_actor.name = "sidebar";
        gtk_actor.x_expand = true;
        gtk_actor.y_expand = true;

        notebook.get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);
        notebook.set_size_request ((int) width, 100);
        notebook.show_tabs = false;

        /* SidebarPage.COLLECTION */
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        notebook.append_page (vbox, null);

        /* SidebarPage.WIZARD */
        vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        vbox.margin_top = 20;
        notebook.append_page (vbox, null);

        /* SidebarPage.PROPERTIES */
        vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
        notebook.append_page (vbox, null);

        notebook.show_all ();
    }
}
