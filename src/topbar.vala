using Clutter;
using Gtk;

class Boxes.Topbar: Boxes.UI {
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
        this.height = 50;

        this.setup_topbar ();
    }

    private void setup_topbar () {
        this.notebook = new Gtk.Notebook ();
        this.notebook.set_size_request (50, (int)this.height);
        this.actor = new GtkClutter.Actor.with_contents (this.notebook);
        this.app.box.pack (this.actor,
                           "column", 0,
                           "row", 0,
                           "column-span", 2,
                           "x-expand", true,
                           "y-expand", false);

        this.hbox = new Gtk.HBox (false, 0);
        this.hbox.get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);

        this.corner = new Gtk.EventBox ();
        // FIXME.. this.corner.get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);
        this.hbox.pack_start (this.corner, false, false, 0);

        this.toolbar_start = new Gtk.Toolbar ();
        this.toolbar_start.icon_size = Gtk.IconSize.MENU;
        this.toolbar_start.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        var back = new Gtk.ToolButton (null, null);
        back.icon_name =  "go-previous-symbolic";
        back.get_style_context ().add_class ("raised");
        back.clicked.connect ( (button) => { this.app.go_back (); });
        this.toolbar_start.insert (back, 0);
        this.toolbar_start.set_show_arrow (false);
        this.hbox.pack_start (this.toolbar_start, false, false, 0);

        this.label = new Gtk.Label ("New and Recent");
        this.label.name = "TopbarLabel";
        this.label.set_halign (Gtk.Align.START);
        this.hbox.pack_start (this.label, true, true, 0);

        var toolbar_end = new Gtk.Toolbar ();
        toolbar_end.icon_size = Gtk.IconSize.MENU;
        toolbar_end.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        this.spinner = new Gtk.ToolButton (new Gtk.Spinner (), null);
        this.spinner.get_style_context ().add_class ("raised");
        toolbar_end.insert (this.spinner, 0);
        toolbar_end.set_show_arrow (false);
        this.hbox.pack_start (toolbar_end, false, false, 0);

        this.notebook.append_page (this.hbox, null);
        this.notebook.page = 0;
        this.notebook.show_tabs = false;
        this.notebook.show_all ();

        this.app.state.set_key (null,
                                "display",
                                this.actor,
                                "y",
                                AnimationMode.EASE_OUT_QUAD,
                                -(float) this.height,
                                0,
                                0); // FIXME: make it dynamic depending on topbar size..
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.COLLECTION:
            this.toolbar_start.hide ();
            this.spinner.hide ();

            break;

        case UIState.CREDS:
            this.toolbar_start.show ();
            this.spinner.show ();

            break;

        case UIState.DISPLAY:
            pin_actor(this.actor);

            break;

        default:
            break;
        }
    }
}

