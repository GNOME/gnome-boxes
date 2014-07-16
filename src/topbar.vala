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
    private CollectionToolbar collection_toolbar;
    [GtkChild]
    private SelectionToolbar selection_toolbar;
    [GtkChild]
    private DisplayToolbar display_toolbar;
    [GtkChild]
    public WizardToolbar wizard_toolbar;

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
            wizard_toolbar.click_back_button ();
            break;
        }
    }

    // Clicks the appropriate forward button dependent on the ui state.
    public void click_forward_button () {
        wizard_toolbar.click_forward_button ();
    }

    // Clicks the appropriate cancel button dependent on the ui state.
    public void click_cancel_button () {
        switch (App.app.ui_state) {
        case UIState.COLLECTION:
            if (App.app.selection_mode)
                App.app.selection_mode = false;
            return;
        case UIState.WIZARD:
            wizard_toolbar.cancel_btn.clicked ();
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
            props_toolbar.title = _("%s - Properties").printf (App.window.current_item.name);
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

        transition_type = Gtk.StackTransitionType.CROSSFADE; // FIXME: Why this won't work from .ui file?
    }

    public void setup_ui () {
        assert (App.window != null);

        App.app.notify["selection-mode"].connect (() => {
            page = App.app.selection_mode ?
                TopbarPage.SELECTION : page = TopbarPage.COLLECTION;
        });

        var toolbar = App.window.display_page.toolbar;
        toolbar.bind_property ("title", display_toolbar, "title", BindingFlags.SYNC_CREATE);
        toolbar.bind_property ("subtitle", display_toolbar, "subtitle", BindingFlags.SYNC_CREATE);

        collection_toolbar.setup_ui ();
        selection_toolbar.setup_ui ();
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
            props_name_bind = App.window.current_item.bind_property ("name",
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
}
