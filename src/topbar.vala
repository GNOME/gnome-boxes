// This file is part of GNOME Boxes. License: LGPLv2
using Clutter;
using Gtk;

private class Boxes.Topbar: Boxes.UI {
    public Widget corner;
    public Gtk.Label label;

    private App app;
    private uint height;

    private Actor actor; // the topbar box
    private Notebook notebook;

    private HBox hbox;
    private Toolbar toolbar_start;
    private ToolButton spinner;

    public Topbar (App app) {
        this.app = app;
        height = 50;

        setup_topbar ();
    }

    private void setup_topbar () {
        notebook = new Gtk.Notebook ();
        notebook.set_size_request (50, (int) height);
        actor = new GtkClutter.Actor.with_contents (notebook);
        app.box.pack (actor,
                      "column", 0,
                      "row", 0,
                      "column-span", 2,
                      "x-expand", true,
                      "y-expand", false);

        hbox = new Gtk.HBox (false, 0);
        hbox.get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);

        corner = new Gtk.EventBox ();
        // FIXME.. corner.get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);
        hbox.pack_start (corner, false, false, 0);

        toolbar_start = new Gtk.Toolbar ();
        toolbar_start.icon_size = Gtk.IconSize.MENU;
        toolbar_start.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        var back = new Gtk.ToolButton (null, null);
        back.icon_name =  "go-previous-symbolic";
        back.get_style_context ().add_class ("raised");
        back.clicked.connect ((button) => { app.go_back (); });
        toolbar_start.insert (back, 0);
        toolbar_start.set_show_arrow (false);
        hbox.pack_start (toolbar_start, false, false, 0);

        label = new Gtk.Label ("New and Recent");
        label.name = "TopbarLabel";
        label.set_halign (Gtk.Align.START);
        hbox.pack_start (label, true, true, 0);

        var toolbar_end = new Gtk.Toolbar ();
        toolbar_end.icon_size = Gtk.IconSize.MENU;
        toolbar_end.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        spinner = new Gtk.ToolButton (new Gtk.Spinner (), null);
        spinner.get_style_context ().add_class ("raised");
        toolbar_end.insert (spinner, 0);
        toolbar_end.set_show_arrow (false);
        hbox.pack_start (toolbar_end, false, false, 0);

        notebook.append_page (hbox, null);
        notebook.page = 0;
        notebook.show_tabs = false;
        notebook.show_all ();

        // FIXME: make it dynamic depending on topbar size..:
        app.state.set_key (null, "display", actor, "y", AnimationMode.EASE_OUT_QUAD, -(float) height, 0, 0);
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.COLLECTION:
            toolbar_start.hide ();
            spinner.hide ();
            break;

        case UIState.CREDS:
            toolbar_start.show ();
            spinner.show ();
            break;

        case UIState.DISPLAY:
            pin_actor (actor);
            break;

        default:
            break;
        }
    }
}

