// This file is part of GNOME Boxes. License: LGPLv2+

private enum Boxes.SourcePage {
    MAIN,
    URL,

    LAST,
}

public delegate bool ClickedFunc ();

/* Subclass of ScrolledWindow that shows at allocates enough
   space to not scroll for at most N children. */
[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-scrolled.ui")]
private class Boxes.WizardScrolled : Gtk.ScrolledWindow {
    [GtkChild]
    public Gtk.Box vbox;

    private int num_visible;
    public WizardScrolled (int num_visible) {
        this.num_visible = num_visible;

        notify["num-visible"].connect (() => {
            queue_resize ();
        });
        get_vscrollbar ().show.connect (() => {
            this.get_style_context ().add_class ("boxes-menu-scrolled");
            this.reset_style ();
        });
        get_vscrollbar ().hide.connect ( () => {
            this.get_style_context ().remove_class ("boxes-menu-scrolled");
            this.reset_style ();
        });
    }

    public override void get_preferred_height (out int minimum_height, out int natural_height) {
        base.get_preferred_height (out minimum_height, out natural_height);
        var viewport = get_child () as Gtk.Viewport;
        var box = viewport.get_child () as Gtk.Box;

        int height = 0;
        int i = 0;
        foreach (var w in box.get_children ()) {
            if (!w.get_visible ())
                continue;
            int child_height;
            w.get_preferred_height (null, out child_height);
            height += child_height;
            i++;
            if (i == num_visible)
                break;
        }
        minimum_height = int.max (minimum_height, height);
        natural_height = int.max (natural_height, height);
    }
}

private class Boxes.WizardSource: GLib.Object {
    public Gtk.Widget widget { get { return notebook; } }
    public Gtk.Widget? selected { get; set; }
    private SourcePage _page;
    public SourcePage page {
        get { return _page; }
        set {
            _page = value;
            notebook.set_current_page (page);
            if (selected != null)
                selected.grab_focus ();
            switch (page) {
            case SourcePage.MAIN:
                add_media_entries.begin ();
                // FIXME: grab first element in the menu list
                main_vbox.grab_focus ();
                break;
            case SourcePage.URL:
                url_entry.changed ();
                url_entry.grab_focus ();
                break;
            }
        }
    }
    public string uri {
        get { return url_entry.get_text (); }
        set { url_entry.set_text (value); }
    }
    public InstallerMedia? install_media { get; private set; }
    public LibvirtSystemImporter libvirt_sys_importer { get; private set; }
    public bool libvirt_sys_import;

    private Gtk.Box main_vbox;
    private Gtk.Box media_vbox;
    private Boxes.WizardScrolled media_scrolled;
    private Gtk.Notebook notebook;
    private Gtk.Label url_label;
    private Gtk.Image url_image;
    public Gtk.Entry url_entry;

    public signal void activate (); // Emitted on user activating a source

    private MediaManager media_manager;

    public WizardSource (MediaManager media_manager) {
        this.media_manager = media_manager;

        notebook = new Gtk.Notebook ();
        notebook.width_request = 500;
        notebook.get_style_context ().add_class ("boxes-source-nb");
        notebook.show_tabs = false;

        /* main page */
        main_vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        main_vbox.get_style_context ().add_class ("boxes-menu");
        main_vbox.margin_top = main_vbox.margin_bottom = 15;
        main_vbox.grab_focus ();
        notebook.append_page (main_vbox, null);

        media_scrolled = new WizardScrolled (5);
        media_vbox = media_scrolled.vbox;
        main_vbox.add (media_scrolled);

        var hbox = add_entry (main_vbox, () => {
            page = SourcePage.URL;

            return false;
        });
        var label = new Gtk.Label (_("Enter URL"));
        label.xalign = 0.0f;
        hbox.pack_start (label, true, true);
        var next = new Gtk.Label ("▶");
        hbox.pack_start (next, false, false);

        hbox = add_entry (main_vbox, launch_file_selection_dialog);
        label = new Gtk.Label (_("Select a file"));
        label.xalign = 0.0f;
        hbox.pack_start (label, true, true);
        next = new Gtk.Label ("▶");
        hbox.pack_start (next, false, false);

        /* URL page */
        var url_menubox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        url_menubox.get_style_context ().add_class ("boxes-menu");
        url_menubox.margin_top = url_menubox.margin_bottom = 15;
        notebook.append_page (url_menubox, null);

        hbox = add_entry (url_menubox, () => {
            selected = null;
            page = SourcePage.MAIN;

            return false;
        });
        var prev = new Gtk.Label ("◀");
        hbox.pack_start (prev, false, false);
        label = new Gtk.Label (_("Enter URL"));
        label.get_style_context ().add_class ("boxes-source-label");
        hbox.pack_start (label, true, true);

        var vbox = add_entry (url_menubox);
        vbox.set_orientation (Gtk.Orientation.VERTICAL);
        url_entry = new Gtk.Entry ();
        vbox.add (url_entry);

        hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        url_image = new Gtk.Image.from_icon_name ("network-workgroup", 0);
        // var image = new Gtk.Image.from_icon_name ("krfb", 0);
        url_image.pixel_size = 96;
        hbox.pack_start (url_image, false, false);

        url_label = new Gtk.Label (null);
        url_label.xalign = 0.0f;
        url_label.set_markup (_("<b>Desktop Access</b>\n\nWill add boxes for all systems available from this account."));
        url_label.set_use_markup (true);
        url_label.wrap = true;

        hbox.pack_start (url_label, true, true);
        vbox.add (hbox);

        notebook.show_all ();

        add_libvirt_sytem_entry.begin ();
        add_media_entries.begin ();
    }

    public void update_url_page(string title, string text, string icon_name) {
        url_label.set_markup ("<b>"  + title + "</b>\n\n" + text);
        url_image.icon_name = icon_name;
    }

    private async void add_media_entries () {
        var medias = yield media_manager.list_installer_medias ();

        foreach (var child in media_vbox.get_children ()) {
            var child_media = child.get_data<string> ("boxes-media");
            if (child_media == null)
                continue;

            var obsolete = true;
            foreach (var media in medias)
                if (child_media == media.device_file) {
                    obsolete = false;

                    break;
                }

            if (obsolete)
                media_vbox.remove (child);
        }

        foreach (var media in medias) {
            var nouveau = true; // Everyone speaks some French, right? :)
            foreach (var child in media_vbox.get_children ()) {
                var child_media = child.get_data<string> ("boxes-media");
                if (child_media  != null && child_media == media.device_file) {
                    nouveau = false;

                    break;
                }
            }

            if (nouveau)
                add_media_entry (media);
        }

        // In case we removed everything
        if (media_vbox.get_children ().length () == 0)
            media_scrolled.hide ();
    }

    private void add_media_entry (InstallerMedia media) {
        var hbox = add_entry (media_vbox, () => {
            on_media_selected (media);

            return true;
        }, 15, 5, media.device_file);

        var image = new Gtk.Image.from_icon_name ("media-optical", 0);
        image.pixel_size = 64;
        hbox.pack_start (image, false, false);

        if (media.os != null)
            Downloader.fetch_os_logo.begin (image, media.os, 64);

        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 5);
        vbox.homogeneous = true;
        hbox.pack_start (vbox, true, true);

        var media_label = media.label;
        if (media.os_media != null && media.os_media.live)
            // Translators: We show 'Live' tag next or below the name of live OS media or box based on such media.
            //              http://en.wikipedia.org/wiki/Live_CD
            media_label += " (" +  _("Live") + ")";
        var label = new Gtk.Label (media_label);
        label.set_ellipsize (Pango.EllipsizeMode.END);
        label.get_style_context ().add_class ("boxes-source-label");
        label.xalign = 0.0f;
        vbox.pack_start (label, true, true);

        if (media.os_media != null) {
            var architecture = (media.os_media.architecture == "i386" || media.os_media.architecture == "i686") ?
                               _("32-bit x86 system") :
                               _("64-bit x86 system");
            label = new Gtk.Label (architecture);
            label.set_ellipsize (Pango.EllipsizeMode.END);
            label.get_style_context ().add_class ("boxes-step-label");
            label.xalign = 0.0f;
            vbox.pack_start (label, true, true);

            if (media.os.vendor != null)
                // Translator comment: %s is name of vendor here (e.g Canonical Ltd or Red Hat Inc)
                label.label += _(" from %s").printf (media.os.vendor);
        }

        media_vbox.show_all ();
        media_scrolled.show ();
    }

    private async void add_libvirt_sytem_entry () {
        try {
            libvirt_sys_importer = yield new LibvirtSystemImporter ();
        } catch (LibvirtSystemImporterError.NO_IMPORTS error) {
            debug ("%s", error.message);

            return;
        }

        var hbox = add_entry (main_vbox, () => {
            libvirt_sys_import = true;
            activate ();

            return true;
        });
        var label = new Gtk.Label (libvirt_sys_importer.wizard_menu_label);
        label.xalign = 0.0f;
        hbox.pack_start (label, true, true);
        var next = new Gtk.Label ("▶");
        hbox.pack_start (next, false, false);
        main_vbox.show_all ();
    }

    private Gtk.Box add_entry (Gtk.Box            box,
                               owned ClickedFunc? clicked = null,
                               int                h_margin = 20,
                               int                v_margin = 10,
                               string?            media = null) {
        Gtk.Container row;
        if (clicked != null) {
            var button = new Gtk.Button ();
            button.clicked.connect (() => {
                if (clicked ())
                    selected = button;
            });
            row = button;
        } else {
            var bin = new Gtk.Alignment (0,0,1,1);
            draw_as_css_box (bin);
            row = bin;
        }
        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
        row.add (hbox);
        row.get_style_context ().add_class ("boxes-menu-row");

        box.add (row);
        if (media != null)
            row.set_data ("boxes-media", media);

        hbox.margin_left = hbox.margin_right = h_margin;
        hbox.margin_top = hbox.margin_bottom = v_margin;

        return hbox;
    }

    private bool launch_file_selection_dialog () {
        var dialog = new Gtk.FileChooserDialog (_("Select a device or ISO file"),
                                                App.app.window,
                                                Gtk.FileChooserAction.OPEN,
                                                _("_Cancel"), Gtk.ResponseType.CANCEL,
                                                _("_Open"), Gtk.ResponseType.ACCEPT);
        dialog.show_hidden = false;
        dialog.filter = new Gtk.FileFilter ();
        dialog.filter.add_mime_type ("application/x-cd-image");
        foreach (var extension in InstalledMedia.supported_extensions)
            dialog.filter.add_pattern ("*" + extension);
        var ret = false;
        if (dialog.run () == Gtk.ResponseType.ACCEPT) {
            uri = dialog.get_uri ();
            // clean install_media as this may be set already when going back in the wizard
            install_media = null;
            activate ();

            ret = true;
        }

        dialog.destroy ();

        return ret;
    }

    private void on_media_selected (InstallerMedia media) {
        try {
            install_media = media_manager.create_installer_media_from_media (media);
            uri = media.device_file;
            activate ();
        } catch (GLib.Error error) {
            // This is unlikely to happen since media we use as template should have already done most async work
            warning ("Failed to setup installation media '%s': %s", media.device_file, error.message);
        }
    }
}
