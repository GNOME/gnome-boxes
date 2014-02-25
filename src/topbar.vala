// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

public enum Boxes.TopbarPage {
    COLLECTION,
    SELECTION,
    WIZARD,
    PROPERTIES,
    DISPLAY
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/topbar.ui")]
private class Boxes.Topbar: Gtk.Notebook, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    [GtkChild]
    public Gtk.Button wizard_cancel_btn;
    [GtkChild]
    public Gtk.Button wizard_back_btn;
    [GtkChild]
    public Gtk.Button wizard_continue_btn;
    [GtkChild]
    public Gtk.Button wizard_create_btn;

    [GtkChild]
    private Gtk.Spinner spinner;
    [GtkChild]
    private Gtk.Button search_btn;
    [GtkChild]
    private Gtk.Button search2_btn;
    [GtkChild]
    private Gtk.Button select_btn;
    [GtkChild]
    private Gtk.Button back_btn;
    [GtkChild]
    private Gtk.Image back_image;
    [GtkChild]
    private Gtk.Button new_btn;
    [GtkChild]
    private Gtk.MenuButton selection_menu_button;
    [GtkChild]
    private Gtk.HeaderBar collection_toolbar;
    [GtkChild]
    private DisplayToolbar display_toolbar;

    [GtkChild]
    private Gtk.HeaderBar props_toolbar;
    [GtkChild]
    private Gtk.Image props_back_image;

    private GLib.Binding props_name_bind;

    public string? _status;
    public string? status {
        get { return _status; }
        set {
            _status = value;
            collection_toolbar.set_title (_status);
            display_toolbar.set_title (_status);
        }
    }

    public string properties_title {
        set {
            // Translators: The %s will be replaced with the name of the VM
            props_toolbar.title = _("%s - Properties").printf (App.app.current_item.name);
        }
    }

    construct {
        notify["ui-state"].connect (ui_state_changed);

        App.app.notify["selected-items"].connect (() => {
            update_selection_label ();
        });
    }

    public void setup_ui () {
        var back_icon = (get_direction () == Gtk.TextDirection.RTL)? "go-previous-rtl-symbolic" :
                                                                     "go-previous-symbolic";
        back_image.set_from_icon_name (back_icon, Gtk.IconSize.MENU);
        props_back_image.set_from_icon_name (back_icon, Gtk.IconSize.MENU);

        assert (App.window != null);
        assert (App.window.searchbar != null);
        search_btn.bind_property ("active", App.window.searchbar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);
        search2_btn.bind_property ("active", App.window.searchbar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);

        App.app.notify["selection-mode"].connect (() => {
            page = App.app.selection_mode ?
                TopbarPage.SELECTION : page = TopbarPage.COLLECTION;
        });
        update_select_btn ();
        App.app.collection.item_added.connect (update_select_btn);
        App.app.collection.item_removed.connect (update_select_btn);
        update_selection_label ();

        var toolbar = App.window.display_page.toolbar;
        toolbar.bind_property ("title", display_toolbar, "title", BindingFlags.SYNC_CREATE);
        toolbar.bind_property ("subtitle", display_toolbar, "subtitle", BindingFlags.SYNC_CREATE);

        update_search_btn ();
        App.app.collection.item_added.connect (update_search_btn);
        App.app.collection.item_removed.connect (update_search_btn);
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
            page = TopbarPage.COLLECTION;
            back_btn.hide ();
            spinner.hide ();
            select_btn.show ();
            search_btn.show ();
            new_btn.show ();
            break;

        case UIState.CREDS:
            page = TopbarPage.COLLECTION;
            new_btn.hide ();
            back_btn.show ();
            spinner.show ();
            select_btn.hide ();
            search_btn.hide ();
            break;

        case UIState.DISPLAY:
            page = TopbarPage.DISPLAY;
            spinner.hide ();
            break;

        case UIState.PROPERTIES:
            page = TopbarPage.PROPERTIES;
            props_name_bind = App.app.current_item.bind_property ("name",
                                                                  this, "properties-title",
                                                                  BindingFlags.SYNC_CREATE);
            break;

        case UIState.WIZARD:
            page = TopbarPage.WIZARD;
            break;

        default:
            break;
        }
    }

    [GtkCallback]
    private void on_new_btn_clicked () {
        App.app.set_state (UIState.WIZARD);
    }

    [GtkCallback]
    private void on_back_btn_clicked () {
        App.app.set_state (UIState.COLLECTION);
    }

    [GtkCallback]
    private void on_select_btn_clicked () {
        App.app.selection_mode = true;
    }

    [GtkCallback]
    private void on_cancel_btn_clicked () {
        App.app.selection_mode = false;
    }

    [GtkCallback]
    private void on_props_back_btn_clicked () {
        App.app.set_state (App.app.previous_ui_state);
    }
}
