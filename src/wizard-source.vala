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
                // FIXME: grab first element in the menu list
                main_menubox.grab_focus ();
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

    private Boxes.MenuBox main_menubox;
    private Gtk.Notebook notebook;
    private Gtk.Label url_label;
    private Gtk.Image url_image;
    public Gtk.Entry url_entry;

    MediaManager media_manager;

    public WizardSource (MediaManager media_manager) {
        this.media_manager = media_manager;

        notebook = new Gtk.Notebook ();
        notebook.width_request = 500;
        notebook.get_style_context ().add_class ("boxes-source-nb");
        notebook.show_tabs = false;

        /* main page */
        main_menubox = new Boxes.MenuBox (Gtk.Orientation.VERTICAL);
        main_menubox.margin_top = main_menubox.margin_bottom = 15;
        main_menubox.grab_focus ();
        notebook.append_page (main_menubox, null);

        var hbox = add_entry (main_menubox, () => { page = SourcePage.URL; });
        var label = new Gtk.Label (_("Enter URL"));
        label.xalign = 0.0f;
        hbox.pack_start (label, true, true);
        var next = new Gtk.Label ("▶");
        hbox.pack_start (next, false, false);

        var separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        main_menubox.pack_start (separator, false, false);

        hbox = add_entry (main_menubox, launch_file_selection_dialog);
        label = new Gtk.Label (_("Select a file"));
        label.xalign = 0.0f;
        hbox.pack_start (label, true, true);
        next = new Gtk.Label ("▶");
        hbox.pack_start (next, false, false);

        /* URL page */
        var url_menubox = new Boxes.MenuBox (Gtk.Orientation.VERTICAL);
        url_menubox.margin_top = url_menubox.margin_bottom = 15;
        notebook.append_page (url_menubox, null);

        hbox = add_entry (url_menubox, () => { page = SourcePage.MAIN; });
        var prev = new Gtk.Label ("◀");
        hbox.pack_start (prev, false, false);
        label = new Gtk.Label (_("Enter URL"));
        label.get_style_context ().add_class ("boxes-source-label");
        hbox.pack_start (label, true, true);
        separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        url_menubox.add (separator);
        hbox = add_entry (url_menubox);
        url_entry = new Gtk.Entry ();
        hbox.add (url_entry);
        hbox = add_entry (url_menubox);

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

        add_media_entries ();

        notebook.show_all ();
    }

    public void update_url_page(string title, string text, string icon_name) {
        url_label.set_markup ("<b>"  + title + "</b>\n\n" + text);
        url_image.icon_name = icon_name;
    }

    private async void add_media_entries () {
        foreach (var media in media_manager.medias)
            add_media_entry (media);

        media_manager.media_available.connect ((media) => {
            add_media_entry (media);
        });

        media_manager.media_unavailable.connect ((media) => {
            foreach (var child in main_menubox.get_children ())
                if (child.name != null && child.name.has_prefix (media.device_file))
                    main_menubox.remove (child);

            if (install_media != null && install_media.device_file == media.device_file) {
                install_media = null;
                uri = media.device_file;
            }
        });
    }

    private void add_media_entry (InstallerMedia media) {
        var hbox = add_entry (main_menubox, () => {
            install_media = media;
            uri = media.device_file;
            url_entry.activate ();
        }, 5, 10, true, media.device_file + "-item");

        var image = new Gtk.Image.from_icon_name ("media-optical", 0);
        image.pixel_size = 96;
        hbox.pack_start (image, false, false);

        var vbox = new Gtk.VBox (false, 0);
        hbox.pack_start (vbox, true, true);

        var label = new Gtk.Label (media.label);
        label.xalign = 0.0f;
        label.yalign = 0.2f;
        vbox.pack_start (label, true, true);
        label = new Gtk.Label (_("Local Machine: Will create a new local box"));
        label.xalign = 0.0f;
        label.yalign = 0.1f;
        vbox.pack_start (label, true, true);

        var separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        separator.name = media.device_file + "-separator";
        main_menubox.pack_start (separator, false, false);
        main_menubox.reorder_child (separator, 1);

        main_menubox.show_all ();
    }

    private Gtk.HBox add_entry (MenuBox            box,
                                owned ClickedFunc? clicked = null,
                                int                h_margin = 20,
                                int                v_margin = 10,
                                bool               beginning = false,
                                string?            name = null) {
        var hbox = new Gtk.HBox (false, 20);
        var item = new MenuBox.Item (hbox);
        box.add (item);
        if (beginning)
            main_menubox.reorder_child (item, 0);
        if (name != null)
            item.name = name;

        hbox.margin_left = hbox.margin_right = h_margin;
        hbox.margin_top = hbox.margin_bottom = v_margin;

        if (clicked != null) {
            item.selectable = true;
            box.selected.connect ((widget) => {
                if (widget == item)
                    clicked ();
            });
        }

        return hbox;
    }

    private void launch_file_selection_dialog () {
        var dialog = new Gtk.FileChooserDialog (_("Select a device or ISO file"),
                                                null,
                                                Gtk.FileChooserAction.OPEN,
                                                Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                                                Gtk.Stock.OPEN, Gtk.ResponseType.ACCEPT);
        dialog.show_hidden = false;
        dialog.local_only = true;
        if (dialog.run () == Gtk.ResponseType.ACCEPT) {
            uri = dialog.get_uri ();
            url_entry.activate ();
        }

        dialog.hide ();
    }
}
