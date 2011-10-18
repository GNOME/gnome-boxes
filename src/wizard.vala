// This file is part of GNOME Boxes. License: LGPLv2

private enum Boxes.WizardPage {
    INTRODUCTION,
    SOURCE,
    PREPARATION,
    SETUP,
    REVIEW,

    LAST,
}

private class Boxes.Wizard: Boxes.UI {
    public override Clutter.Actor actor { get { return gtk_actor; } }

    private GtkClutter.Actor gtk_actor;
    private Boxes.App app;
    private GenericArray<Gtk.Label> steps;
    private Gtk.Notebook notebook;
    private Gtk.Button back_button;
    private Gtk.Button next_button;

    private WizardPage _page;
    private WizardPage page {
        get { return _page; }
        set {
            if (value == WizardPage.LAST) {
                app.go_back ();
            }

            _page = value;
            notebook.set_current_page (value);

            for (var i = 0; i < steps.length; i++) {
                var label = steps.get (i);
                label.modify_fg (Gtk.StateType.NORMAL, null);
            }

            /* highlight in white current page label */
            Gdk.Color white;
            Gdk.Color.parse ("white", out white);
            steps.get (page).modify_fg (Gtk.StateType.NORMAL, white);

            back_button.set_sensitive (page != WizardPage.INTRODUCTION);
            next_button.set_label (page != WizardPage.REVIEW ? _("Continue") : _("Create"));
        }
    }

    construct {
        steps = new GenericArray<Gtk.Label> ();
        steps.length = WizardPage.LAST;
    }

    public Wizard (App app) {
        this.app = app;

        setup_ui ();
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

    private void setup_ui () {
        notebook = new Gtk.Notebook ();
        notebook.show_tabs = false;
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);

        /* Introduction */
        var hbox = new Gtk.HBox (false, 10);
        add_step (hbox, _("Introduction"), WizardPage.INTRODUCTION);
        hbox.add (new Gtk.Image.from_stock ("gtk-dialog-warning", Gtk.IconSize.DIALOG));
        var la = new Gtk.Label (null);
        la.set_markup (_("Creating a Box will allow you to use another operating system directly from your existing login.\n\nYou may connect to an existing machine <b><i>over the network</i></b> or create a <b><i>virtual machine</i></b> that runs locally on your own."));
        la.set_use_markup (true);
        la.wrap = true;
        hbox.add (la);
        hbox.show_all ();

        /* Source */
        var vbox = new Gtk.VBox (false, 10);
        add_step (vbox, _("Source Selection"), WizardPage.SOURCE);
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
            app.go_back ();
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
