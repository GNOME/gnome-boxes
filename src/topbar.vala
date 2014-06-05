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
private class Boxes.Topbar: Gtk.Stack, Boxes.UI {
    private const string[] page_names = { "collection", "selection", "wizard", "properties", "display" };

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
    private Gtk.Button search2_btn;
    [GtkChild]
    private Gtk.Label selection_menu_button_label;
    [GtkChild]
    private CollectionToolbar collection_toolbar;
    [GtkChild]
    private DisplayToolbar display_toolbar;

    [GtkChild]
    private Gtk.HeaderBar props_toolbar;

    private GLib.Binding props_name_bind;

    // Clicks the appropriate back button depending on the ui state.
    public void click_back_button () {
        switch (App.app.ui_state) {
        case UIState.PROPERTIES:
            break;
        case UIState.CREDS:
            collection_toolbar.click_back_button ();
            break;
        case UIState.WIZARD:
            if (App.window.wizard.page != WizardPage.INTRODUCTION)
                wizard_back_btn.clicked ();
            break;
        }
    }

    // Clicks the appropriate forward button dependent on the ui state.
    public void click_forward_button () {
        if (App.window.wizard.page != WizardPage.REVIEW)
            wizard_continue_btn.clicked ();
    }

    // Clicks the appropriate cancel button dependent on the ui state.
    public void click_cancel_button () {
        switch (App.app.ui_state) {
        case UIState.COLLECTION:
            if (App.app.selection_mode)
                App.app.selection_mode = false;
            return;
        case UIState.WIZARD:
            wizard_cancel_btn.clicked ();
            return;
        }
    }

    public string? _status;
    public string? status {
        get { return _status; }
        set {
            _status = value;
            collection_toolbar.set_title (_status??"");
            display_toolbar.set_title (_status??"");
        }
    }

    public string properties_title {
        set {
            // Translators: The %s will be replaced with the name of the VM
            props_toolbar.title = _("%s - Properties").printf (App.app.current_item.name);
        }
    }

    private TopbarPage _page;
    public TopbarPage page {
        get { return _page; }
        set {
            _page = value;

            visible_child_name = page_names[value];
        }
    }

    construct {
        notify["ui-state"].connect (ui_state_changed);

        App.app.notify["selected-items"].connect (() => {
            update_selection_label ();
        });
        transition_type = Gtk.StackTransitionType.CROSSFADE; // FIXME: Why this won't work from .ui file?
    }

    public void setup_ui () {
        assert (App.window != null);
        assert (App.window.searchbar != null);
        search2_btn.bind_property ("active", App.window.searchbar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);

        App.app.notify["selection-mode"].connect (() => {
            page = App.app.selection_mode ?
                TopbarPage.SELECTION : page = TopbarPage.COLLECTION;
        });
        update_selection_label ();

        var toolbar = App.window.display_page.toolbar;
        toolbar.bind_property ("title", display_toolbar, "title", BindingFlags.SYNC_CREATE);
        toolbar.bind_property ("subtitle", display_toolbar, "subtitle", BindingFlags.SYNC_CREATE);

        update_search_btn ();
        App.app.collection.item_added.connect (update_search_btn);
        App.app.collection.item_removed.connect (update_search_btn);

        collection_toolbar.setup_ui ();
    }

    private void update_search_btn () {
        search2_btn.sensitive = App.app.collection.items.length != 0;
    }

    private void update_selection_label () {
        var items = App.app.selected_items.length ();
        if (items > 0) {
            // This goes with the "Click on items to select them" string and is about selection of items (boxes)
            // when the main collection view is in selection mode.
            selection_menu_button_label.label = ngettext ("%d selected", "%d selected", items).printf (items);
        } else {
            selection_menu_button_label.label = _("(Click on items to select them)");
        }
    }

    private void ui_state_changed () {
        switch (ui_state) {
        case UIState.COLLECTION:
            page = TopbarPage.COLLECTION;
            break;

        case UIState.CREDS:
            page = TopbarPage.COLLECTION;
            break;

        case UIState.DISPLAY:
            page = TopbarPage.DISPLAY;
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
    private void on_cancel_btn_clicked () {
        App.app.selection_mode = false;
    }
}
