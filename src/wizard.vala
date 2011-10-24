// This file is part of GNOME Boxes. License: LGPLv2+

private enum Boxes.WizardPage {
    INTRODUCTION,
    SOURCE,
    PREPARATION,
    SETUP,
    REVIEW,

    LAST,
}

private enum Boxes.SourcePage {
    MAIN,
    URL,
    FILE,

    LAST,
}

public delegate void ClickedFunc ();

private class Boxes.WizardSource: GLib.Object {
    public Gtk.Widget widget { get { return notebook; } }
    private SourcePage _page;
    public SourcePage page {
        get { return _page; }
        set {
            _page = value;
            notebook.set_current_page (page);
        }
    }
    public string uri {
        get { return url_entry.get_text (); }
    }

    private Gtk.Notebook notebook;
    private Gtk.Entry url_entry;

    public WizardSource () {
        notebook = new Gtk.Notebook ();
        notebook.get_style_context ().add_class ("boxes-source-nb");
        notebook.show_tabs = false;

        /* main page */
        var vbox = new Gtk.VBox (false, 10);
        vbox.margin_top = vbox.margin_bottom = 15;
        notebook.append_page (vbox, null);

        var hbox = add_entry (vbox, () => { page = SourcePage.URL; });
        var label = new Gtk.Label (_("Enter URL"));
        label.xalign = 0.0f;
        hbox.pack_start (label, true, true);
        var next = new Gtk.Label ("▶");
        hbox.pack_start (next, false, false);

        var separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        separator.height_request = 5;
        vbox.pack_start (separator, false, false);

        hbox = add_entry (vbox, () => { page = SourcePage.FILE; });
        label = new Gtk.Label (_("Select a file"));
        label.xalign = 0.0f;
        hbox.pack_start (label, true, true);
        next = new Gtk.Label ("▶");
        hbox.pack_start (next, false, false);

        /* URL page */
        vbox = new Gtk.VBox (false, 10);
        vbox.margin_top = vbox.margin_bottom = 15;
        notebook.append_page (vbox, null);

        hbox = add_entry (vbox, () => { page = SourcePage.MAIN; });
        var prev = new Gtk.Label ("◀");
        hbox.pack_start (prev, false, false);
        label = new Gtk.Label (_("Enter URL"));
        label.get_style_context ().add_class ("boxes-source-label");
        hbox.pack_start (label, true, true);
        separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        separator.height_request = 5;
        vbox.pack_start (separator, false, false);
        hbox = add_entry (vbox);
        url_entry = new Gtk.Entry ();
        hbox.add (url_entry);
        hbox = add_entry (vbox);
        var image = new Gtk.Image.from_icon_name ("network-workgroup", 0);
        // var image = new Gtk.Image.from_icon_name ("krfb", 0);
        image.pixel_size = 96;
        hbox.pack_start (image, false, false);
        label = new Gtk.Label (null);
        label.xalign = 0.0f;
        label.set_markup (_("<b>Desktop Access</b>\n\nWill add boxes for all systems available from this account."));
        label.set_use_markup (true);
        label.wrap = true;
        hbox.pack_start (label, true, true);

        notebook.show_all ();
    }

    private Gtk.HBox add_entry (Gtk.VBox vbox, ClickedFunc? clicked = null) {
        var ebox = new Gtk.EventBox ();
        ebox.visible_window = false;
        var hbox = new Gtk.HBox (false, 20);
        ebox.add (hbox);
        vbox.pack_start (ebox, false, false);
        hbox.margin_left = hbox.margin_right = 20;
        if (clicked != null) {
            ebox.add_events (Gdk.EventMask.BUTTON_PRESS_MASK);
            ebox.button_press_event.connect (() => {
                clicked ();
                return true;
            });
        }

        return hbox;
    }
}

private class Boxes.WizardSummary: GLib.Object {
    public Gtk.Widget widget { get { return table; } }
    private Gtk.Table table;
    private uint current_row;

    public WizardSummary () {
        table = new Gtk.Table (1, 2, false);
        table.margin = 20;
        table.row_spacing = 10;
        table.column_spacing = 20;

        clear ();
    }

    public void add_property (string name, string? value) {
        if (value == null)
            return;

        var label_name = new Gtk.Label (name);
        label_name.modify_fg (Gtk.StateType.NORMAL, get_color ("grey"));
        label_name.xalign = 1.0f;
        table.attach_defaults (label_name, 0, 1, current_row, current_row + 1);

        var label_value = new Gtk.Label (value);
        label_value.modify_fg (Gtk.StateType.NORMAL, get_color ("white"));
        label_value.xalign = 0.0f;
        table.attach_defaults (label_value, 1, 2, current_row, current_row + 1);

        current_row += 1;
        table.show_all ();
    }

    public void clear () {
        foreach (var child in table.get_children ()) {
            table.remove (child);
        }

        table.resize (1, 2);

        var label = new Gtk.Label (_("Will create a new box with the following properties:"));
        label.margin_bottom = 10;
        label.xalign = 0.0f;
        table.attach_defaults (label, 0, 2, 0, 1);
        current_row = 1;
    }
}

private class Boxes.Wizard: Boxes.UI {
    public override Clutter.Actor actor { get { return gtk_actor; } }

    private GtkClutter.Actor gtk_actor;
    private Boxes.App app;
    private GenericArray<Gtk.Label> steps;
    private Gtk.Notebook notebook;
    private Gtk.Button back_button;
    private Gtk.Button next_button;
    private Boxes.WizardSource wizard_source;
    private Boxes.WizardSummary summary;
    private CollectionSource? source;

    private WizardPage _page;
    private WizardPage page {
        get { return _page; }
        set {
            if (value == WizardPage.REVIEW) {
                try {
                    prepare ();
                } catch (Boxes.Error e) {
                    warning ("Fixme: %s".printf (e.message));
                    return;
                }
            } else if (value == WizardPage.LAST) {
                if (!create ())
                    return;
                app.ui_state = UIState.COLLECTION;
            }

            if (skip_page (value)) {
                page = value > page ? value + 1 : value - 1;
                return;
            }

            _page = value;
            notebook.set_current_page (value);

            for (var i = 0; i < steps.length; i++) {
                var label = steps.get (i);
                label.modify_fg (Gtk.StateType.NORMAL, null);
            }

            /* highlight in white current page label */
            steps.get (page).modify_fg (Gtk.StateType.NORMAL, get_color ("white"));

            back_button.set_sensitive (page != WizardPage.INTRODUCTION);
            next_button.set_label (page != WizardPage.REVIEW ? _("Continue") : _("Create"));
        }
    }

    construct {
        steps = new GenericArray<Gtk.Label> ();
        steps.length = WizardPage.LAST;
        wizard_source = new Boxes.WizardSource ();
    }

    public Wizard (App app) {
        this.app = app;

        setup_ui ();
    }

    private bool create () {
        if (source == null)
            return false;

        source.save ();
        app.add_collection_source (source);
        return true;
    }

    private void prepare_with_uri (string text) throws Boxes.Error {
        bool uncertain;

        var mimetype = ContentType.guess (text, null, out uncertain);
        var uri = Xml.URI.parse (text);

        if (uncertain) {
            if (uri.server == null)
                throw new Boxes.Error.INVALID ("the URI is invalid");

            if (uri.scheme == "spice" || uri.scheme == "vnc") {
                var query = new Query (uri.query_raw ?? uri.query);

                source = new CollectionSource (uri.server, uri.scheme, text);
                summary.add_property (_("Type"), uri.scheme.up ());
                summary.add_property (_("Host"), uri.server.down ());
                summary.add_property (_("Port"), query.get ("port"));
                summary.add_property (_("TLS Port"), query.get ("tls-port"));
            } else
                throw new Boxes.Error.INVALID ("Unsupported protocol");
        } else {
            debug ("FIXME: %s".printf (mimetype));
        }
    }

    private void prepare () throws Boxes.Error {
        summary.clear ();

        if (this.wizard_source.page == Boxes.SourcePage.URL ||
            this.wizard_source.page == Boxes.SourcePage.FILE) {
            prepare_with_uri (this.wizard_source.uri);
        }
    }

    private void add_step (Gtk.Widget widget, string label, WizardPage page) {
        notebook.append_page (widget, null);

        /* sidebar */
        var vbox = app.sidebar.notebook.get_nth_page (Boxes.SidebarPage.WIZARD) as Gtk.VBox;

        var la = new Gtk.Label (label);
        la.margin_left = 25;
        la.get_style_context ().add_class ("boxes-step-label");
        la.set_halign (Gtk.Align.START);
        vbox.pack_start (la, false, false, 10);

        vbox.show_all ();
        steps.set (page, la);
    }

    private bool skip_page (Boxes.WizardPage page) {
        if (page > Boxes.WizardPage.SOURCE &&
            page < Boxes.WizardPage.REVIEW &&
            this.wizard_source.page == Boxes.SourcePage.URL)
            return true;

        return false;
    }

    private void setup_ui () {
        notebook = new Gtk.Notebook ();
        notebook.show_tabs = false;
        notebook.get_style_context ().add_class ("boxes-bg");
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);

        /* Introduction */
        var hbox = new Gtk.HBox (false, 10);
        hbox.margin_right = 20;
        add_step (hbox, _("Introduction"), WizardPage.INTRODUCTION);
        hbox.add (new Gtk.Image.from_file (get_pixmap ("boxes-create.png")));
        var la = new Gtk.Label (null);
        la.set_markup (_("Creating a Box will allow you to use another operating system directly from your existing login.\n\nYou may connect to an existing machine <b><i>over the network</i></b> or create a <b><i>virtual machine</i></b> that runs locally on your own."));
        la.set_use_markup (true);
        la.wrap = true;
        hbox.add (la);
        hbox.show_all ();

        /* Source */
        var vbox = new Gtk.VBox (false, 20);
        vbox.margin = 15;
        add_step (vbox, _("Source Selection"), WizardPage.SOURCE);
        la = new Gtk.Label (_("Insert operating system installation media or select a source below"));
        la.wrap = true;
        vbox.pack_start (la, false, false);
        vbox.pack_start (wizard_source.widget, false, false);
        vbox.show_all ();

        /* Preparation */
        vbox = new Gtk.VBox (false, 10);
        add_step (vbox, _("Preparation"), WizardPage.PREPARATION);
        vbox.show_all ();

        /* Setup */
        vbox = new Gtk.VBox (false, 10);
        add_step (vbox, _("Setup"), WizardPage.SETUP);
        vbox.show_all ();

        /* Review */
        vbox = new Gtk.VBox (false, 10);
        add_step (vbox, _("Review"), WizardPage.REVIEW);
        summary = new Boxes.WizardSummary ();
        vbox.pack_start (summary.widget, false, false);
        vbox.show_all ();

        /* topbar */
        hbox = app.topbar.notebook.get_nth_page (Boxes.TopbarPage.WIZARD) as Gtk.HBox;

        la = new Gtk.Label (_("Create a Box"));
        la.name = "TopbarLabel";
        la.margin_left = 20;
        la.set_halign (Gtk.Align.START);
        hbox.pack_start (la, true, true, 0);

        var hbox_end = new Gtk.HBox (false, 0);
        hbox.pack_start (hbox_end, false, false, 0);
        hbox_end.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);
        var cancel = new Gtk.Button.from_stock (Gtk.Stock.CANCEL);
        hbox_end.pack_start (cancel, false, false, 15);
        cancel.clicked.connect (() => {
            app.ui_state = UIState.COLLECTION;
        });
        back_button = new Gtk.Button.from_stock (Gtk.Stock.GO_BACK);
        hbox_end.pack_start (back_button, false, false, 5);
        back_button.clicked.connect (() => {
            page = page - 1;
        });

        next_button = new Gtk.Button.with_label (_("Continue"));
        hbox_end.pack_start (next_button, false, false, 0);
        next_button.clicked.connect (() => {
            page = page + 1;
        });
        next_button.get_style_context ().add_class ("boxes-continue");

        hbox.show_all ();
        notebook.show_all ();
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.WIZARD:
            page = WizardPage.INTRODUCTION;
            break;
        }
    }
}
