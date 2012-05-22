// This file is part of GNOME Boxes. License: LGPLv2+

private enum Boxes.SourcePage {
    MAIN,
    URL,

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

    private Gtk.Box main_vbox;
    private Gtk.Box media_vbox;
    private Gtk.Notebook notebook;
    private Gtk.Label url_label;
    private Gtk.Image url_image;
    public Gtk.Entry url_entry;

    private MediaManager media_manager;
    private Boxes.App app;

    public WizardSource (Boxes.App app, MediaManager media_manager) {
        this.app = app;
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

        media_vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        main_vbox.add (media_vbox);

        var hbox = add_entry (main_vbox, () => { page = SourcePage.URL; });
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

        hbox = add_entry (url_menubox, () => { page = SourcePage.MAIN; });
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
                main_vbox.remove (child);
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
    }

    private void add_media_entry (InstallerMedia media) {
        var hbox = add_entry (media_vbox, () => {
            install_media = media;
            uri = media.device_file;
            url_entry.activate ();
            page = SourcePage.URL;
        }, 15, 5, media.device_file);

        var image = get_os_logo (media.os, 64);
        hbox.pack_start (image, false, false);

        var vbox = new Gtk.VBox (true, 5);
        hbox.pack_start (vbox, true, true);

        var label = new Gtk.Label (media.label);
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
                clicked ();
            });
            row = button;
        } else {
            var bin = new Gtk.Alignment (0,0,1,1);
            bin.draw.connect ((cr) => {
                var context = bin.get_style_context ();
                Gtk.Allocation allocation;
                bin.get_allocation (out allocation);
                context.render_background (cr,
                                           0, 0,
                                           allocation.width, allocation.height);
                context.render_frame (cr,
                                      0, 0,
                                      allocation.width, allocation.height);
                return false;
            });
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

    private void launch_file_selection_dialog () {
        var dialog = new Gtk.FileChooserDialog (_("Select a device or ISO file"),
                                                app.window,
                                                Gtk.FileChooserAction.OPEN,
                                                Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                                                Gtk.Stock.OPEN, Gtk.ResponseType.ACCEPT);
        dialog.show_hidden = false;
        dialog.local_only = true;
        dialog.filter = new Gtk.FileFilter ();
        dialog.filter.add_mime_type ("application/x-cd-image");
        if (dialog.run () == Gtk.ResponseType.ACCEPT) {
            uri = dialog.get_uri ();
            url_entry.activate ();
            page = SourcePage.URL;
        }

        dialog.hide ();
    }
}
