// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gtk;

public enum Boxes.TopbarPage {
    COLLECTION,
    SELECTION,
    WIZARD,
    PROPERTIES
}

private class Boxes.Topbar: Boxes.UI {
    public override Clutter.Actor actor { get { return gtk_actor; } }

    private GtkClutter.Actor gtk_actor; // the topbar box
    public Notebook notebook;

    private Gtk.Spinner spinner;
    private Gtk.ToggleButton search_btn;
    private Gtk.ToggleButton search2_btn;
    private Gtk.Button select_btn;
    private Gtk.Button done_btn;
    private Gtk.Button back_btn;
    private Gtk.Button new_btn;
    private Gd.MainToolbar selection_toolbar;
    private Gd.MainToolbar collection_toolbar;

    public string? _status;
    public string? status {
        get { return _status; }
        set { _status = value; collection_toolbar.set_labels (_status, null); }
    }

    public Topbar () {
        setup_topbar ();

        App.app.notify["selected-items"].connect (() => {
            update_selection_label ();
        });
    }

    private void setup_topbar () {
        notebook = new Gtk.Notebook ();
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);
        gtk_actor.name = "topbar";

        /* TopbarPage.COLLECTION */
        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        notebook.append_page (hbox, null);

        var toolbar = new Gd.MainToolbar ();
        collection_toolbar = toolbar;
        toolbar.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);
        hbox.pack_start (toolbar, true, true, 0);

        new_btn = toolbar.add_button (null, _("New"), true) as Gtk.Button;
        new_btn.set_size_request (70, -1);
        new_btn.clicked.connect ((button) => { App.app.ui_state = UIState.WIZARD; });

        back_btn = toolbar.add_button ("go-previous-symbolic", null, true) as Gtk.Button;
        back_btn.clicked.connect ((button) => { App.app.ui_state = UIState.COLLECTION; });

        // We need a sizegroup to ensure the spinner is the same size
        // as the buttons so it centers correctly
        var spinner_sizegroup = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);

        spinner = new Gtk.Spinner ();
        spinner.start ();
        spinner.hexpand = true;
        spinner.vexpand = true;
        spinner.margin = 6;
        toolbar.add_widget (spinner, false);
        spinner_sizegroup.add_widget (spinner);

        search_btn = toolbar.add_toggle ("edit-find-symbolic", null, false) as Gtk.ToggleButton;
        search_btn.bind_property ("active", App.app.searchbar, "visible", BindingFlags.BIDIRECTIONAL);

        select_btn = toolbar.add_button ("object-select-symbolic", null, false) as Gtk.Button;
        spinner_sizegroup.add_widget (select_btn);
        select_btn.clicked.connect (() => {
            App.app.selection_mode = true;
        });
        App.app.notify["selection-mode"].connect (() => {
            notebook.page = App.app.selection_mode ?
                TopbarPage.SELECTION : notebook.page = TopbarPage.COLLECTION;
        });
        update_select_btn ();
        App.app.collection.item_added.connect (update_select_btn);
        App.app.collection.item_removed.connect (update_select_btn);

        /* TopbarPage.SELECTION */
        hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        notebook.append_page (hbox, null);
        selection_toolbar = new Gd.MainToolbar ();
        selection_toolbar.get_style_context ().add_class ("selection-mode");
        selection_toolbar.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        var menu = new GLib.Menu ();
        menu.append (_("Select All"), "app.select-all");
        menu.append (_("Select Running"), "app.select-running");
        menu.append (_("Select None"), "app.select-none");

        selection_toolbar.set_labels_menu (menu);
        hbox.pack_start (selection_toolbar, true, true, 0);

        update_selection_label ();

        search2_btn = selection_toolbar.add_toggle ("edit-find-symbolic", null, false) as Gtk.ToggleButton;
        search2_btn.bind_property ("active", App.app.searchbar, "visible", BindingFlags.BIDIRECTIONAL);

        done_btn = selection_toolbar.add_button (null, _("_Done"), false) as Gtk.Button;
        done_btn.get_style_context().add_class("suggested-action");
        done_btn.use_stock = true;
        done_btn.clicked.connect (() => {
            App.app.selection_mode = false;
        });

        /* TopbarPage.WIZARD */
        hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        notebook.append_page (hbox, null);

        /* TopbarPage.PROPERTIES */
        hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        notebook.append_page (hbox, null);


        update_search_btn ();
        App.app.collection.item_added.connect (update_search_btn);
        App.app.collection.item_removed.connect (update_search_btn);

        notebook.show_tabs = false;
        notebook.show_all ();
    }

    private void update_search_btn () {
        search_btn.sensitive = App.app.collection.items.length != 0;
        search2_btn.sensitive = App.app.collection.items.length != 0;
    }

    private void update_select_btn () {
        select_btn.sensitive = App.app.collection.items.length != 0;
    }

    private void update_selection_label () {
        var items = App.app.selected_items.length ();
        if (items > 0)
            // This goes with the "Click on items to select them" string and is about selection of items (boxes)
            // when the main collection view is in selection mode.
            selection_toolbar.set_labels (ngettext ("%d selected", "%d selected", items).printf (items), null);
        else
            selection_toolbar.set_labels (null, _("(Click on items to select them)"));
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.COLLECTION:
            notebook.page = TopbarPage.COLLECTION;
            back_btn.hide ();
            spinner.hide ();
            select_btn.show ();
            search_btn.show ();
            new_btn.show ();
            break;

        case UIState.CREDS:
            notebook.page = TopbarPage.COLLECTION;
            new_btn.hide ();
            back_btn.show ();
            spinner.show ();
            select_btn.hide ();
            search_btn.hide ();
            break;

        case UIState.DISPLAY:
            break;

        case UIState.PROPERTIES:
            notebook.page = TopbarPage.PROPERTIES;
            break;

        case UIState.WIZARD:
            notebook.page = TopbarPage.WIZARD;
            break;

        default:
            break;
        }
    }
}
