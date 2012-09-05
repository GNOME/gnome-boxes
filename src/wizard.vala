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
    private GenericArray<Gtk.Label> steps;
    private Gtk.Notebook notebook;
    private Gtk.Button cancel_button;
    private Gtk.Button back_button;
    private Gtk.Button next_button;
    private Boxes.WizardSource wizard_source;
    private WizardSummary summary;
    private CollectionSource? source;
    private Gtk.ProgressBar prep_progress;
    private Gtk.VBox setup_vbox;
    private Gtk.Label review_label;
    private Gtk.Label nokvm_label;
    private Gtk.Image installer_image;

    private MediaManager media_manager;

    private VMCreator? vm_creator;
    private LibvirtMachine? machine;

    private WizardPage _page;
    private WizardPage page {
        get { return _page; }
        set {
            back_button.sensitive = value != WizardPage.INTRODUCTION;

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
                case WizardPage.SOURCE:
                    wizard_source.selected = null;
                    wizard_source.page = SourcePage.MAIN;
                    break;

                case WizardPage.PREPARATION:
                    if (!prepare ())
                        return;
                    break;

                case WizardPage.SETUP:
                    if (!setup ())
                        return;
                    break;

                case WizardPage.REVIEW:
                    next_button.sensitive = false;

                    review.begin ((obj, result) => {
                        next_button.sensitive = true;
                        if (!review.end (result))
                            page = page - 1;
                    });
                    break;

                case WizardPage.LAST:
                    skip_review_for_live = false;
                    if (create ())
                       App.app.ui_state = UIState.COLLECTION;
                    else
                       App.app.notificationbar.display_error (_("Box creation failed"));
                    return;
                }
            } else {
                switch (page) {
                case WizardPage.REVIEW:
                    destroy_machine ();
                    break;
                }
            }

            if (skip_page (value))
                return;

            _page = value;
            notebook.set_current_page (value);

            for (var i = 0; i < steps.length; i++) {
                var label = steps.get (i);
                label.modify_fg (Gtk.StateType.NORMAL, null);
            }

            /* highlight in white current page label */
            steps.get (page).modify_fg (Gtk.StateType.NORMAL, get_color ("white"));

            next_button.label = page != WizardPage.REVIEW ? _("C_ontinue") : _("C_reate");
        }
    }

    construct {
        steps = new GenericArray<Gtk.Label> ();
        steps.length = WizardPage.LAST;
        media_manager = new MediaManager ();
    }

    private void wizard_source_update_next () {
        next_button.sensitive = false;

        switch (wizard_source.page) {
        case Boxes.SourcePage.MAIN:
            next_button.sensitive = wizard_source.selected != null;
            break;

        case Boxes.SourcePage.URL:
            next_button.sensitive = wizard_source.uri.length != 0;

            var text = _("Please enter desktop or collection URI");
            var icon = "preferences-desktop-remote-desktop";
            try {
                prepare_for_location (this.wizard_source.uri, true);

                if (source != null && source.source_type == "libvirt") {
                    text = _("Will add boxes for all systems available from this account.");
                    icon = "network-workgroup";
                } else
                    text = _("Will add a single box.");

            } catch (GLib.Error error) {
                // ignore any parsing error
            }

            wizard_source.update_url_page (_("Desktop Access"), text, icon);
            break;

        default:
            warn_if_reached ();
            break;
        }
    }

    public Wizard () {
        wizard_source = new Boxes.WizardSource (media_manager);
        wizard_source.notify["page"].connect(wizard_source_update_next);
        wizard_source.notify["selected"].connect(wizard_source_update_next);
        wizard_source.url_entry.changed.connect (wizard_source_update_next);

        wizard_source.url_entry.activate.connect(() => {
            page = WizardPage.PREPARATION;
        });

        setup_ui ();
    }

    public void cleanup () {
        destroy_machine ();
    }

    private bool create () {
        if (source == null) {
            return_val_if_fail (vm_creator != null, false); // Shouldn't arrive here with source & vm_creator being null

            next_button.sensitive = false;
            try {
                vm_creator.launch_vm (machine);
            } catch (GLib.Error error) {
                warning (error.message);

                return false;
            }

            vm_creator = null;
            machine = null;
            wizard_source.uri = "";

            return true;
        }

        source.save ();
        App.app.add_collection_source.begin (source);
        return true;
    }

    private void prepare_for_location (string location, bool probing = false) throws GLib.Error {
        source = null;

        if (location == "")
            throw new Boxes.Error.INVALID ("empty location");

        var file = File.new_for_commandline_arg (location);

        if (file.is_native ()) {
            // FIXME: We should able to handle non-local URIs here too
            if (!probing)
                prepare_for_installer (file.get_path ());
        } else {
            bool uncertain;
            var uri = file.get_uri ();

            var mimetype = ContentType.guess (uri, null, out uncertain);

            if (uncertain)
                prepare_for_uri (uri);
            else
                debug ("FIXME: %s".printf (mimetype));
        }
    }

    private void prepare_for_uri (string uri_as_text) throws Boxes.Error {
        var uri = Xml.URI.parse (uri_as_text);

        if (uri == null)
            throw new Boxes.Error.INVALID (_("Invalid URI"));

        source = new CollectionSource (uri.server ?? uri_as_text, uri.scheme, uri_as_text);

        if (uri.scheme == "spice" ||
            uri.scheme == "vnc") {
            // accept any vnc:// or spice:// uri
        } else if (uri.scheme.has_prefix ("qemu")) {
            // accept any qemu..:// uri
            source.source_type = "libvirt";
        } else
            throw new Boxes.Error.INVALID (_("Unsupported protocol '%s'").printf (uri.scheme));
    }

    private void prepare_for_installer (string path) throws GLib.Error {
        next_button.sensitive = false;
        media_manager.create_installer_media_for_path.begin (path, null, on_installer_media_instantiated);
    }

    private void on_installer_media_instantiated (Object? source_object, AsyncResult result) {
        next_button.sensitive = true;

        try {
            var install_media = media_manager.create_installer_media_for_path.end (result);
            vm_creator = new VMCreator (install_media);
            if (install_media.os == null) {
                 prep_progress.fraction = 1.0;
                 page = WizardPage.SETUP;

                return;
            }

            Downloader.fetch_os_logo.begin (installer_image, install_media.os, 128, (object, result) => {
                Downloader.fetch_os_logo.end (result);

                prep_progress.fraction = 1.0;
                page = WizardPage.SETUP;
            });
        } catch (IOError.CANCELLED cancel_error) { // We did this, so no warning!
        } catch (GLib.Error error) {
            App.app.notificationbar.display_error (error.message);
            page = WizardPage.SOURCE;
        }
    }

    private bool prepare () {
        installer_image.set_from_icon_name ("media-optical", 0); // Reset

        if (this.wizard_source.install_media != null) {
            vm_creator = new VMCreator (this.wizard_source.install_media);
            prep_progress.fraction = 1.0;
            page = WizardPage.SETUP;
            return false;
        } else {
            try {
                prepare_for_location (this.wizard_source.uri);
            } catch (GLib.Error error) {
                App.app.notificationbar.display_error (error.message);

                return false;
            }

            return true;
        }
    }

    private bool setup () {
        // there is no setup yet for direct source
        if (source != null)
            return true;

        return_if_fail (vm_creator != null);

        vm_creator.install_media.bind_property ("user-data-for-vm-creation-available",
                                                next_button, "sensitive",
                                                BindingFlags.SYNC_CREATE);
        vm_creator.install_media.populate_setup_vbox (setup_vbox);

        return true;
    }

    private Cancellable? review_cancellable;

    private async bool review () {
        // only one outstanding review () permitted
        return_if_fail (review_cancellable == null);

        review_cancellable = new Cancellable ();
        var result = yield do_review_cancellable ();
        review_cancellable = null;

        return result;
    }

    private async bool do_review_cancellable () {
        return_if_fail (review_cancellable != null);

        nokvm_label.hide ();
        summary.clear ();

        if (vm_creator != null && machine == null) {
            try {
                machine = yield vm_creator.create_vm (review_cancellable);
            } catch (IOError.CANCELLED cancel_error) { // We did this, so ignore!
                return false;
            } catch (GLib.Error error) {
                App.app.notificationbar.display_error (_("Box setup failed"));
                warning (error.message);

                return false;
            }
        }

        if (review_cancellable.is_cancelled ())
            return false;

        review_label.set_text (_("Will create a new box with the following properties:"));

        if (source != null) {
            var uri = Xml.URI.parse (source.uri);

            summary.add_property (_("Type"), source.source_type);

            if (uri != null && uri.server != null)
                summary.add_property (_("Host"), uri.server.down ());
            else
                summary.add_property (_("URI"), source.uri.down ());

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

            if (source.source_type == "libvirt") {
                review_label.set_text (_("Will add boxes for all systems available from this account:"));
            }
        } else if (machine != null) {
            foreach (var property in vm_creator.install_media.get_vm_properties ())
                summary.add_property (property.first, property.second);

            try {
                var config = null as GVirConfig.Domain;
                yield run_in_thread (() => { config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE); });

                var memory = format_size (config.memory * Osinfo.KIBIBYTES, FormatSizeFlags.IEC_UNITS);
                summary.add_property (_("Memory"), memory);
            } catch (GLib.Error error) {
                warning ("Failed to get configuration for machine '%s': %s", machine.name, error.message);
            }

            if (machine.storage_volume != null) {
                try {
                    var volume_info = machine.storage_volume.get_info ();
                    var capacity = format_size (volume_info.capacity, FormatSizeFlags.IEC_UNITS);
                    summary.add_property (_("Disk"),  _("%s maximum".printf (capacity)));
                } catch (GLib.Error error) {
                    warning ("Failed to get information on volume '%s': %s",
                             machine.storage_volume.get_name (),
                             error.message);
                }
            }

            nokvm_label.visible = (machine.domain_config.get_virt_type () != GVirConfig.DomainVirtType.KVM);
        }

        summary.append_customize_button (() => {
            // Selecting an item in UIState.WIZARD implies changing state to UIState.PROPERTIES
            App.app.select_item (machine);
        });

        return true;
    }

    private void add_step (Gtk.Widget widget, string title, WizardPage page) {
        notebook.append_page (widget, null);

        /* sidebar */
        var vbox = App.app.sidebar.notebook.get_nth_page (Boxes.SidebarPage.WIZARD) as Gtk.VBox;

        var label = new Gtk.Label (title);
        label.margin_left = 25;
        label.get_style_context ().add_class ("boxes-step-label");
        label.set_halign (Gtk.Align.START);
        vbox.pack_start (label, false, false, 10);

        vbox.show_all ();
        steps.set (page, label);
    }

    private bool skip_review_for_live;

    private bool skip_page (Boxes.WizardPage page) {
        var forwards = page > this.page;
        var skip_to = page;

        // remote-display case
        if (source != null &&
            Boxes.WizardPage.SOURCE < page < Boxes.WizardPage.REVIEW)
            skip_to = forwards ? page + 1 : page - 1;

        // always skip preparation step backwards
        if (!forwards &&
            page == Boxes.WizardPage.PREPARATION)
            skip_to = page - 1;

        if (vm_creator != null) {
            // Skip SETUP page if installer media doesn't need it
            if (page == Boxes.WizardPage.SETUP &&
                !vm_creator.install_media.need_user_input_for_vm_creation)
                    skip_to = forwards ? page + 1 : page - 1;

            // Skip review for live media if told to do so
            if (page == Boxes.WizardPage.REVIEW && forwards
                && vm_creator.install_media.live
                && skip_review_for_live)
                    skip_to += 1;
        }

        if (skip_to != page) {
            this.page = skip_to;
            return true;
        }

        return false;
    }

    private void setup_ui () {
        notebook = new Gtk.Notebook ();
        notebook.margin = 15;
        notebook.width_request = 500;
        notebook.show_tabs = false;
        notebook.get_style_context ().add_class ("boxes-bg");
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);
        gtk_actor.get_widget ().get_style_context ().add_class ("boxes-bg");
        gtk_actor.name = "wizard";
        gtk_actor.opacity = 0;

        /* Introduction */
        var hbox = new Gtk.HBox (false, 10);
        hbox.halign = Gtk.Align.CENTER;
        add_step (hbox, _("Introduction"), WizardPage.INTRODUCTION);
        hbox.add (new Gtk.Image.from_file (get_pixmap ("boxes-create.png")));
        var label = new Gtk.Label (null);
        label.get_style_context ().add_class ("boxes-wizard-label");
        label.set_markup (_("Creating a Box will allow you to use another operating system directly from your existing login.\n\nYou may connect to an existing machine <b><i>over the network</i></b> or create a <b><i>virtual machine</i></b> that runs locally on your own."));
        label.wrap = true;
        // Work around clutter size allocation issue (bz#677260)
        label.width_chars = 30;
        label.max_width_chars = 40;
        hbox.add (label);
        hbox.show_all ();

        /* Source */
        var vbox = new Gtk.VBox (false, 30);
        vbox.valign = Gtk.Align.CENTER;
        vbox.halign = Gtk.Align.CENTER;
        add_step (vbox, _("Source Selection"), WizardPage.SOURCE);
        label = new Gtk.Label (_("Insert operating system installation media or select a source below"));
        label.get_style_context ().add_class ("boxes-wizard-label");
        label.wrap = true;
        // Work around clutter size allocation issue (bz#677260)
        label.width_chars = 30;
        label.xalign = 0.0f;
        vbox.pack_start (label, false, false);
        vbox.pack_start (wizard_source.widget, false, false);
        wizard_source.widget.hexpand = true;
        wizard_source.widget.halign = Gtk.Align.CENTER;
        label = new Gtk.Label (_("Any trademarks shown above are used merely for identification of software products you have already obtained and are the property of their respective owners."));
        label.get_style_context ().add_class ("boxes-logo-notice-label");
        label.wrap = true;
        // Work around clutter size allocation issue (bz#677260)
        label.width_chars = 30;
        label.max_width_chars = 50;
        vbox.pack_start (label, false, false);
        vbox.show_all ();

        /* Preparation */
        vbox = new Gtk.VBox (false, 30);
        vbox.valign = Gtk.Align.CENTER;
        vbox.halign = Gtk.Align.CENTER;
        add_step (vbox, _("Preparation"), WizardPage.PREPARATION);
        label = new Gtk.Label (_("Preparing to create new box"));
        label.get_style_context ().add_class ("boxes-wizard-label");
        label.wrap = true;
        // Work around clutter size allocation issue (bz#677260)
        label.width_chars = 30;
        label.xalign = 0.0f;
        vbox.pack_start (label, false, false);

        hbox = new Gtk.HBox (false, 10);
        hbox.valign = Gtk.Align.CENTER;
        hbox.halign = Gtk.Align.CENTER;
        vbox.pack_start (hbox, true, true);

        installer_image = new Gtk.Image.from_icon_name ("media-optical", 0);
        installer_image.pixel_size = 128;
        hbox.pack_start (installer_image, false, false);
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

        review_label = new Gtk.Label (null);
        review_label.get_style_context ().add_class ("boxes-wizard-label");
        review_label.xalign = 0.0f;
        review_label.wrap = true;
        review_label.width_chars = 30;
        vbox.pack_start (review_label, false, false);

        summary = new WizardSummary ();
        vbox.pack_start (summary.widget, true, true);
        nokvm_label = new Gtk.Label (_("Virtualization extensions are unavailable on your system. Expect this box to be extremely slow. If your system is recent enough (made in or after 2008), these extensions are probably available on your system and you may need to enable them in your system's BIOS setup."));
        nokvm_label.get_style_context ().add_class ("boxes-logo-notice-label");
        nokvm_label.wrap = true;
        nokvm_label.max_width_chars = 50;
        vbox.pack_start (nokvm_label, false, false);
        vbox.show_all ();

        /* topbar */
        hbox = App.app.topbar.notebook.get_nth_page (Boxes.TopbarPage.WIZARD) as Gtk.HBox;
        label = new Gtk.Label (_("Create a Box"));
        label.name = "TopbarLabel";
        label.halign = Gtk.Align.START;
        label.margin_left = 15;
        hbox.pack_start (label, false, false, 0);

        var toolbar = new Gd.MainToolbar ();
        toolbar.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);
        toolbar.toolbar_style = Gtk.ToolbarStyle.TEXT;
        hbox.pack_start (toolbar, true, true, 0);

        cancel_button = toolbar.add_button (null, _("_Cancel"), false) as Gtk.Button;
        cancel_button.use_underline = true;
        cancel_button.clicked.connect (() => {
            destroy_machine ();
            wizard_source.page = SourcePage.MAIN;
            App.app.ui_state = UIState.COLLECTION;
        });

        back_button = toolbar.add_button (null, _("_Back"), false) as Gtk.Button;
        back_button.use_underline = true;
        back_button.clicked.connect (() => {
            page = page - 1;
        });

        next_button = toolbar.add_button (null, _("C_ontinue"), false) as Gtk.Button;
        next_button.use_underline = true;
        next_button.get_style_context ().add_class ("boxes-continue");
        next_button.clicked.connect (() => {
            page = page + 1;
        });

        hbox.show_all ();
        notebook.show_all ();
    }

    public void open_with_uri (string uri, bool skip_review_for_live = true) {
        App.app.ui_state = UIState.WIZARD;
        this.skip_review_for_live = skip_review_for_live;

        page = WizardPage.SOURCE;
        wizard_source.page = SourcePage.URL;
        wizard_source.uri = uri;
        page = WizardPage.PREPARATION;
    }

    public override void ui_state_changed () {
        uint opacity = 0;
        switch (ui_state) {
        case UIState.WIZARD:
            if (previous_ui_state == UIState.PROPERTIES)
                review.begin ();
            else {
                wizard_source.uri = "";
                page = WizardPage.INTRODUCTION;
            }
            opacity = 255;
            break;
        }

        fade_actor (actor, opacity);
    }

    private void destroy_machine () {
        if (review_cancellable != null)
            review_cancellable.cancel ();

        if (machine != null) {
            App.app.delete_machine (machine);
            machine = null;
        }
    }

    private class WizardSummary: GLib.Object {
        public delegate void CustomizeFunc ();

        public Gtk.Widget widget { get { return table; } }
        private Gtk.Table table;
        private uint current_row;

        public WizardSummary () {
            table = new Gtk.Table (1, 3, false);
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

        public void append_customize_button (CustomizeFunc cutomize_func) {
            var button = new Gtk.Button.with_mnemonic (_("C_ustomize..."));
            button.modify_fg (Gtk.StateType.NORMAL, get_color ("white"));
            table.attach_defaults (button, 2, 3, current_row - 1, current_row);
            button.show ();

            button.clicked.connect (() => { cutomize_func (); });
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
