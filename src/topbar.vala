// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gtk;

public enum Boxes.TopbarPage {
    COLLECTION,
    SELECTION,
    WIZARD,
    PROPERTIES,
    DISPLAY
}

private class Boxes.Topbar: GLib.Object, Boxes.UI {
    // FIXME: This is really redundant now that App is using widget property
    // instead but parent Boxes.UI currently requires an actor. Hopefully
    // soon we can move more towards new Gtk classes and Boxes.UI requires
    // a widget property instead.
    public Clutter.Actor actor {
        get {
            if (gtk_actor == null)
                gtk_actor = new Clutter.Actor ();
            return gtk_actor;
        }
    }
    private Clutter.Actor gtk_actor;
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    public Gtk.Widget widget { get { return notebook; } }
    public Notebook notebook;

    private Gtk.Spinner spinner;
    private Gtk.Button search_btn;
    private Gtk.Button search2_btn;
    private Gtk.Button select_btn;
    private Gtk.Button cancel_btn;
    private Gtk.Button back_btn;
    private Gtk.Button new_btn;
    private Gtk.MenuButton selection_menu_button;
    private Gtk.HeaderBar selection_toolbar;
    private Gtk.HeaderBar collection_toolbar;
    private Gtk.HeaderBar display_toolbar;

    public string? _status;
    public string? status {
        get { return _status; }
        set {
            _status = value;
            collection_toolbar.set_title (_status);
            display_toolbar.set_title (_status);
        }
    }

    public Topbar () {
        notify["ui-state"].connect (ui_state_changed);

        setup_topbar ();

        App.app.notify["selected-items"].connect (() => {
            update_selection_label ();
        });
    }

    private void setup_topbar () {
        notebook = new Gtk.Notebook ();

        /* TopbarPage.COLLECTION */
        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        notebook.append_page (hbox, null);

        var toolbar = new Gtk.HeaderBar ();
        toolbar.get_style_context ().add_class ("titlebar");
        collection_toolbar = toolbar;
        toolbar.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);
        toolbar.show_close_button = true;
        hbox.pack_start (toolbar, true, true, 0);

        new_btn = new Gtk.Button.with_mnemonic (_("_New"));
        new_btn.valign = Gtk.Align.CENTER;
        new_btn.get_style_context ().add_class ("text-button");
        toolbar.pack_start (new_btn);
        new_btn.clicked.connect ((button) => { App.app.set_state (UIState.WIZARD); });

        var back_icon = (toolbar.get_direction () == Gtk.TextDirection.RTL)? "go-previous-rtl-symbolic" :
                                                                             "go-previous-symbolic";
        var back_image = new Gtk.Image.from_icon_name (back_icon, Gtk.IconSize.MENU);
        back_btn = new Gtk.Button ();
        back_btn.set_image (back_image);
        back_btn.valign = Gtk.Align.CENTER;
        back_btn.get_style_context ().add_class ("image-button");
        toolbar.pack_start (back_btn);
        back_btn.get_accessible ().set_name (_("Back"));
        back_btn.clicked.connect ((button) => { App.app.set_state (UIState.COLLECTION); });

        // We need a sizegroup to ensure the spinner is the same size
        // as the buttons so it centers correctly
        var spinner_sizegroup = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);

        spinner = new Gtk.Spinner ();
        spinner.start ();
        spinner.hexpand = true;
        spinner.vexpand = true;
        spinner.margin = 6;
        toolbar.pack_end (spinner);
        spinner_sizegroup.add_widget (spinner);

        var search_image = new Gtk.Image.from_icon_name ("edit-find-symbolic", Gtk.IconSize.MENU);
        search_btn = new Gtk.ToggleButton ();
        search_btn.set_image (search_image);
        search_btn.valign = Gtk.Align.CENTER;
        search_btn.get_style_context ().add_class ("image-button");
        toolbar.pack_end (search_btn);
        search_btn.get_accessible ().set_name (_("Search"));
        search_btn.bind_property ("active", App.app.searchbar, "visible", BindingFlags.BIDIRECTIONAL);

        var select_image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.MENU);
        select_btn = new Gtk.Button ();
        select_btn.set_image (select_image);
        select_btn.valign = Gtk.Align.CENTER;
        select_btn.get_style_context ().add_class ("image-button");
        toolbar.pack_end (select_btn);
        select_btn.get_accessible ().set_name (_("Select Items"));
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
        selection_toolbar = new Gtk.HeaderBar ();
        selection_toolbar.get_style_context ().add_class ("selection-mode");
        selection_toolbar.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);
        selection_toolbar.get_style_context ().add_class ("titlebar");

        var menu = new GLib.Menu ();
        menu.append (_("Select All"), "app.select-all");
        menu.append (_("Select Running"), "app.select-running");
        menu.append (_("Select None"), "app.select-none");

        selection_menu_button = new Gtk.MenuButton ();
        selection_menu_button.valign = Gtk.Align.CENTER;
        selection_menu_button.set_menu_model (menu);
        selection_toolbar.set_custom_title (selection_menu_button);
        hbox.pack_start (selection_toolbar, true, true, 0);

        update_selection_label ();

        search_image = new Gtk.Image.from_icon_name ("edit-find-symbolic", Gtk.IconSize.MENU);
        search2_btn = new Gtk.ToggleButton ();
        search2_btn.set_image (search_image);
        search2_btn.valign = Gtk.Align.CENTER;
        search2_btn.get_style_context ().add_class ("image-button");
        selection_toolbar.pack_end (search2_btn);
        search2_btn.bind_property ("active", App.app.searchbar, "visible", BindingFlags.BIDIRECTIONAL);

        cancel_btn = new Gtk.Button.with_mnemonic (_("_Cancel"));
        cancel_btn.valign = Gtk.Align.CENTER;
        cancel_btn.get_style_context ().add_class ("text-button");
        selection_toolbar.pack_end (cancel_btn);
        cancel_btn.clicked.connect (() => {
            App.app.selection_mode = false;
        });

        /* TopbarPage.WIZARD */
        hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        notebook.append_page (hbox, null);

        /* TopbarPage.PROPERTIES */
        hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        notebook.append_page (hbox, null);

        /* TopbarPage.DISPLAY */
        hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        display_toolbar = App.app.display_page.title_toolbar;
        hbox.pack_start (display_toolbar, true, true, 0);
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
        if (items > 0) {
            // This goes with the "Click on items to select them" string and is about selection of items (boxes)
            // when the main collection view is in selection mode.
            selection_menu_button.label = ngettext ("%d selected", "%d selected", items).printf (items);
        } else {
            selection_menu_button.label = _("(Click on items to select them)");
        }
    }

    private void ui_state_changed () {
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
            notebook.page = TopbarPage.DISPLAY;
            spinner.hide ();
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
