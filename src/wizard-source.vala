// This file is part of GNOME Boxes. License: LGPLv2+

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
            switch (page) {
            case SourcePage.MAIN:
                // FIXME: grab first element in the menu list
                menubox.grab_focus ();
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

    private Boxes.MenuBox menubox;
    private Gtk.Notebook notebook;
    private Gtk.Label url_label;
    private Gtk.Image url_image;
    public Gtk.Entry url_entry;

    public WizardSource () {
        notebook = new Gtk.Notebook ();
        notebook.width_request = 500;
        notebook.get_style_context ().add_class ("boxes-source-nb");
        notebook.show_tabs = false;

        /* main page */
        menubox = new Boxes.MenuBox (Gtk.Orientation.VERTICAL);
        menubox.margin_top = menubox.margin_bottom = 15;
        menubox.grab_focus ();
        notebook.append_page (menubox, null);

        var hbox = add_entry (menubox, () => { page = SourcePage.URL; });
        var label = new Gtk.Label (_("Enter URL"));
        label.xalign = 0.0f;
        hbox.pack_start (label, true, true);
        var next = new Gtk.Label ("▶");
        hbox.pack_start (next, false, false);

        var separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        menubox.pack_start (separator, false, false);

        hbox = add_entry (menubox, launch_file_selection_dialog);
        label = new Gtk.Label (_("Select a file"));
        label.xalign = 0.0f;
        hbox.pack_start (label, true, true);
        next = new Gtk.Label ("▶");
        hbox.pack_start (next, false, false);

        /* URL page */
        menubox = new Boxes.MenuBox (Gtk.Orientation.VERTICAL);
        menubox.margin_top = menubox.margin_bottom = 15;
        notebook.append_page (menubox, null);

        hbox = add_entry (menubox, () => { page = SourcePage.MAIN; });
        var prev = new Gtk.Label ("◀");
        hbox.pack_start (prev, false, false);
        label = new Gtk.Label (_("Enter URL"));
        label.get_style_context ().add_class ("boxes-source-label");
        hbox.pack_start (label, true, true);
        separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        menubox.add (separator);
        hbox = add_entry (menubox);
        url_entry = new Gtk.Entry ();
        hbox.add (url_entry);
        hbox = add_entry (menubox);

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

        notebook.show_all ();
    }

    public void update_url_page(string title, string text, string icon_name) {
        url_label.set_markup ("<b>"  + title + "</b>\n\n" + text);
        url_image.icon_name = icon_name;
    }

    private Gtk.HBox add_entry (MenuBox box, ClickedFunc? clicked = null) {
        var hbox = new Gtk.HBox (false, 20);
        var item = new MenuBox.Item (hbox);
        box.add (item);
        hbox.margin_left = hbox.margin_right = 20;
        hbox.margin_top = hbox.margin_bottom = 10;

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
            page = SourcePage.URL;
        }

        dialog.hide ();
    }
}
