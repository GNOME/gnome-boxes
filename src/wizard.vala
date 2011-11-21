// This file is part of GNOME Boxes. License: LGPLv2+

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
    private Boxes.WizardSource wizard_source;
    private WizardSummary summary;
    private CollectionSource? source;
    private Gtk.ProgressBar prep_progress;
    private Gtk.VBox setup_vbox;

    private OSDatabase os_db;
    private VMCreator vm_creator;
    private GUdev.Client client;

    private InstallerMedia? install_media;
    private Osinfo.Resources? resources;

    private WizardPage _page;
    private WizardPage page {
        get { return _page; }
        set {
            var forwards = value > page;

            switch (value) {
            case WizardPage.INTRODUCTION:
                next_button.sensitive = true;
                next_button.grab_focus (); // FIXME: doesn't work?!
                break;

            case WizardPage.SOURCE:
                // reset page to notify deeply widgets states
                wizard_source.page = wizard_source.page;
                break;
            }

            if (forwards) {
                switch (value) {
                case WizardPage.PREPARATION:
                    try {
                        prepare ();
                    } catch (GLib.Error error) {
                        warning ("Fixme: %s".printf (error.message));
                        return;
                    }
                    break;

                case WizardPage.SETUP:
                    setup ();
                    break;

                case WizardPage.REVIEW:
                    review ();
                    break;

                case WizardPage.LAST:
                    if (!create ())
                        return;
                    app.ui_state = UIState.COLLECTION;
                    break;
                }
            }

            if (skip_page (value)) {
                page = forwards ? value + 1 : value - 1;
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

            back_button.sensitive = page != WizardPage.INTRODUCTION;
            next_button.label = page != WizardPage.REVIEW ? _("Continue") : _("Create");
        }
    }

    construct {
        steps = new GenericArray<Gtk.Label> ();
        steps.length = WizardPage.LAST;
        wizard_source = new Boxes.WizardSource ();
        wizard_source.notify["page"].connect(() => {
            if (wizard_source.page == Boxes.SourcePage.MAIN)
                next_button.sensitive = false;
        });
        wizard_source.url_entry.changed.connect (() => {
            // FIXME: add uri checker
            next_button.sensitive = wizard_source.uri.length != 0;
        });
        wizard_source.url_entry.activate.connect(() => {
            page = page + 1;
        });
    }

    public Wizard (App app) {
        this.app = app;

        setup_ui ();
    }

    private bool create () {
        if (source == null) {
            if (install_media == null)
                return false;

            next_button.sensitive = false;
            vm_creator.create_domain_for_installer.begin (install_media, resources, null, on_domain_created);
            install_media = null;
            resources = null;
            wizard_source.uri = "";

            return true;
        }

        source.save ();
        app.add_collection_source (source);
        return true;
    }

    private void on_domain_created (Object? source_object, AsyncResult result) {
        try {
            var domain = vm_creator.create_domain_for_installer.end (result);
            domain.start (0);
        } catch (IOError.CANCELLED cancel_error) { // We did this, so ignore!
        } catch (GLib.Error error) {
            warning ("Fixme: %s".printf (error.message));

            return;
        }

        // Only let the user through if either domain was successfully created or operation was cancelled
        next_button.sensitive = true;
    }

    private void prepare_for_location (string location) throws GLib.Error {
        var file = File.new_for_uri (location);

        if (file.is_native ())
            // FIXME: We should able to handle non-local URIs here too
            prepare_for_installer (location);
        else {
            bool uncertain;

            var mimetype = ContentType.guess (location, null, out uncertain);

            if (uncertain)
                prepare_for_uri (location);
            else
                debug ("FIXME: %s".printf (mimetype));
        }
    }

    private void prepare_for_uri (string uri_as_text) throws Boxes.Error {
        var uri = Xml.URI.parse (uri_as_text);

        if (uri == null || uri.server == null)
            throw new Boxes.Error.INVALID ("the URI is invalid");

        source = new CollectionSource (uri.server, uri.scheme, uri_as_text);

        if (uri.scheme == "spice") {
            if (uri.query_raw == null && uri.query == null)
                throw new Boxes.Error.INVALID ("the Spice URI is incomplete");

            if (uri.port > 0)
                throw new Boxes.Error.INVALID ("the Spice URI is invalid");
        } else if (uri.scheme == "vnc") {
            // accept any vnc:// uri
        } else
            throw new Boxes.Error.INVALID ("Unsupported protocol %s".printf (uri.scheme));
    }

    private void prepare_for_installer (string location) throws GLib.Error {
        if (client == null) {
            client = new GUdev.Client ({"block"});
            os_db = new OSDatabase ();
            vm_creator = new VMCreator (app, "qemu:///session"); // FIXME
        }

        next_button.sensitive = false;
        var file = File.new_for_uri (location);
        // FIXME: Assuming location is a local URI
        InstallerMedia.instantiate.begin (file.get_path (), os_db, client, null, on_installer_media_instantiated);
    }

    private void on_installer_media_instantiated (Object? source_object, AsyncResult result) {
        next_button.sensitive = true;

        try {
            install_media = InstallerMedia.instantiate.end (result);
            resources = os_db.get_resources_for_os (install_media.os);
            prep_progress.fraction = 1.0;
            page = page + 1;
        } catch (IOError.CANCELLED cancel_error) { // We did this, so no warning!
        } catch (GLib.Error error) {
            warning ("Fixme: %s".printf (error.message));
        }
    }

    private void prepare () throws GLib.Error {
        source = null;

        if (this.wizard_source.page == Boxes.SourcePage.URL ||
            this.wizard_source.page == Boxes.SourcePage.FILE)
            prepare_for_location (this.wizard_source.uri);
    }

    private void setup () {
        if (source != null)
            return;

        foreach (var child in setup_vbox.get_children ())
            setup_vbox.remove (child);

        if (install_media == null || !(install_media is UnattendedInstaller)) {
            // Nothing to do so just skip to the next page but let the current page change complete first
            Idle.add (() => {
                page = page + 1;

                return false;
            });

            return;
        }

        var installer = install_media as UnattendedInstaller;
        installer.populate_setup_vbox (setup_vbox);
        setup_vbox.show_all ();
    }

    private void review () {
        summary.clear ();

        if (source != null) {
            var uri = Xml.URI.parse (source.uri);

            summary.add_property (_("Type"), uri.scheme.up ());
            summary.add_property (_("Host"), uri.server.down ());

            switch (uri.scheme) {
            case "spice":
                var query = new Query (uri.query_raw ?? uri.query);

                summary.add_property (_("Port"), query.get ("port"));
                summary.add_property (_("TLS Port"), query.get ("tls-port"));
                break;

            case "vnc":
                if (uri.port > 0)
                    summary.add_property (_("Port"), uri.port.to_string ());
                break;
            }
        } else if (install_media != null)
            summary.add_property (_("System"), install_media.label);
    }

    private void add_step (Gtk.Widget widget, string title, WizardPage page) {
        notebook.append_page (widget, null);

        /* sidebar */
        var vbox = app.sidebar.notebook.get_nth_page (Boxes.SidebarPage.WIZARD) as Gtk.VBox;

        var label = new Gtk.Label (title);
        label.margin_left = 25;
        label.get_style_context ().add_class ("boxes-step-label");
        label.set_halign (Gtk.Align.START);
        vbox.pack_start (label, false, false, 10);

        vbox.show_all ();
        steps.set (page, label);
    }

    private bool skip_page (Boxes.WizardPage page) {
        var backwards = page < this.page;

        // remote-display case
        if (this.source != null &&
            Boxes.WizardPage.SOURCE < page < Boxes.WizardPage.REVIEW)
            return true;

        if (backwards &&
            page == Boxes.WizardPage.PREPARATION)
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
        add_step (hbox, _("Introduction"), WizardPage.INTRODUCTION);
        hbox.add (new Gtk.Image.from_file (get_pixmap ("boxes-create.png")));
        var label = new Gtk.Label (null);
        label.get_style_context ().add_class ("boxes-wizard-label");
        label.set_markup (_("Creating a Box will allow you to use another operating system directly from your existing login.\n\nYou may connect to an existing machine <b><i>over the network</i></b> or create a <b><i>virtual machine</i></b> that runs locally on your own."));
        label.set_use_markup (true);
        label.wrap = true;
        label.halign = Gtk.Align.START;
        hbox.add (label);
        hbox.show_all ();

        /* Source */
        var vbox = new Gtk.VBox (false, 30);
        vbox.valign = Gtk.Align.CENTER;
        vbox.halign = Gtk.Align.CENTER;
        vbox.margin = 15;
        add_step (vbox, _("Source Selection"), WizardPage.SOURCE);
        label = new Gtk.Label (_("Insert operating system installation media or select a source below"));
        label.get_style_context ().add_class ("boxes-wizard-label");
        label.wrap = true;
        label.xalign = 0.0f;
        vbox.pack_start (label, false, false);
        vbox.pack_start (wizard_source.widget, false, false);
        wizard_source.widget.hexpand = true;
        wizard_source.widget.halign = Gtk.Align.CENTER;
        vbox.show_all ();

        /* Preparation */
        vbox = new Gtk.VBox (false, 30);
        vbox.valign = Gtk.Align.CENTER;
        vbox.halign = Gtk.Align.CENTER;
        vbox.margin = 15;
        add_step (vbox, _("Preparation"), WizardPage.PREPARATION);
        label = new Gtk.Label (_("Preparing to create new box"));
        label.get_style_context ().add_class ("boxes-wizard-label");
        label.wrap = true;
        label.xalign = 0.0f;
        vbox.pack_start (label, false, false);

        hbox = new Gtk.HBox (false, 10);
        hbox.valign = Gtk.Align.CENTER;
        hbox.halign = Gtk.Align.CENTER;
        vbox.pack_start (hbox, true, true);

        var image = new Gtk.Image.from_icon_name ("media-optical", 0);
        image.pixel_size = 128;
        hbox.pack_start (image, false, false);
        var prep_vbox = new Gtk.VBox (true, 10);
        prep_vbox.valign = Gtk.Align.CENTER;
        hbox.pack_start (prep_vbox, true, true);
        label = new Gtk.Label (_("Analyzing installer media."));
        label.get_style_context ().add_class ("boxes-wizard-label");
        prep_vbox.pack_start (label, false, false);
        prep_progress = new Gtk.ProgressBar ();
        prep_vbox.pack_start (prep_progress, false, false);
        vbox.show_all ();

        /* Setup */
        setup_vbox = new Gtk.VBox (false, 30);
        setup_vbox.valign = Gtk.Align.CENTER;
        setup_vbox.halign = Gtk.Align.CENTER;
        add_step (setup_vbox, _("Setup"), WizardPage.SETUP);
        setup_vbox.show_all ();

        /* Review */
        vbox = new Gtk.VBox (false, 30);
        vbox.valign = Gtk.Align.CENTER;
        vbox.halign = Gtk.Align.CENTER;
        add_step (vbox, _("Review"), WizardPage.REVIEW);

        label = new Gtk.Label (_("Will create a new box with the following properties:"));
        label.get_style_context ().add_class ("boxes-wizard-label");
        label.xalign = 0.0f;
        vbox.pack_start (label, false, false);

        summary = new WizardSummary ();
        vbox.pack_start (summary.widget, true, true);
        vbox.show_all ();

        /* topbar */
        hbox = app.topbar.notebook.get_nth_page (Boxes.TopbarPage.WIZARD) as Gtk.HBox;

        label = new Gtk.Label (_("Create a Box"));
        label.name = "TopbarLabel";
        label.margin_left = 20;
        label.set_halign (Gtk.Align.START);
        hbox.pack_start (label, true, true, 0);

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
            if (app.uri != null) {
                page = WizardPage.SOURCE;
                wizard_source.page = SourcePage.URL;
                wizard_source.uri = app.uri;
                app.uri = null;
            } else
                page = WizardPage.INTRODUCTION;
            break;
        }
    }

    private class WizardSummary: GLib.Object {
        public Gtk.Widget widget { get { return table; } }
        private Gtk.Table table;
        private uint current_row;

        public WizardSummary () {
            table = new Gtk.Table (1, 2, false);
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
            current_row = 0;
        }
    }
}
