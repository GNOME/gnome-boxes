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
            if (page == SourcePage.URL)
                url_entry.changed ();
        }
    }
    public string uri {
        get { return url_entry.get_text (); }
        set { url_entry.set_text (value); }
    }

    private Gtk.Notebook notebook;
    public Gtk.Entry url_entry;

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
