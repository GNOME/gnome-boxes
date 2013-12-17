// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;
using Clutter;

private enum Boxes.SidebarPage {
    COLLECTION,
    WIZARD,
    PROPERTIES,
}

private class Boxes.Sidebar: Boxes.UI {
    public override Clutter.Actor actor { get { return bin_actor; } }
    public Notebook notebook;
    private uint width;

    public static const int shadow_width = 7;
    private Clutter.Actor bin_actor;
    private GtkClutter.Actor gtk_actor; // the sidebar box

    public Sidebar () {
        width = 200;

        setup_sidebar ();
    }

    public override void ui_state_changed () {
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
        bin_actor = new Clutter.Actor ();
        var bin = new Clutter.BinLayout (Clutter.BinAlignment.START,
                                         Clutter.BinAlignment.START);
        bin_actor.set_layout_manager (bin);
        bin_actor.name = "sidebar-bin";

        var shadow = new Clutter.Actor ();
        shadow.set_width (shadow_width);
        var canvas = new Clutter.Canvas ();
        canvas.draw.connect ( (cr, w, h) => {
            var p = new Cairo.Pattern.linear (0, 0, w, 0);
            p.add_color_stop_rgba (0, 0, 0, 0, 0.4);
            p.add_color_stop_rgba (0.7, 0, 0, 0, 0.0);
            cr.set_source (p);
            cr.set_operator (Cairo.Operator.SOURCE);
            cr.rectangle (0, 0, w, h);
            cr.fill ();

            return true;
        });
        canvas.set_size (shadow_width, 1);
        shadow.set_content (canvas);
        shadow.set_content_gravity (Clutter.ContentGravity.RESIZE_FILL);
        shadow.set_content_scaling_filters (Clutter.ScalingFilter.NEAREST, Clutter.ScalingFilter.NEAREST);
        shadow.x_align = Clutter.ActorAlign.END;
        shadow.x_expand = true;
        shadow.y_expand = true;
        bin_actor.add_child (shadow);

        var background = new GtkClutter.Texture ();
        background.name = "sidebar-background";
        try {
            var pixbuf = load_asset ("boxes-gray.png");
            background.set_from_pixbuf (pixbuf);
        } catch (GLib.Error e) {
            warning ("Failed to load asset 'boxes-gray.png': %s", e.message);
        }
        background.set_repeat (true, true);
        background.set_margin_right (shadow_width);
        background.x_expand = true;
        background.y_expand = true;
        bin_actor.add (background);

        notebook = new Gtk.Notebook ();
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);
        gtk_actor.get_widget ().get_style_context ().add_class ("boxes-bg");
        gtk_actor.name = "sidebar";
        gtk_actor.x_expand = true;
        gtk_actor.y_expand = true;
        bin_actor.add_child (gtk_actor);
        notebook.get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);
        notebook.get_style_context ().add_class ("boxes-bg");
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
