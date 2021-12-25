// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

public enum Boxes.TopbarPage {
    COLLECTION,
    DISPLAY
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/topbar.ui")]
private class Boxes.Topbar: Gtk.Stack, Boxes.UI {
    private const string[] page_names = { "collection", "display" };

    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    [GtkChild]
    private unowned CollectionToolbar collection_toolbar;
    [GtkChild]
    public unowned DisplayToolbar display_toolbar;

    private AppWindow window;

    public void click_back_button () {
        collection_toolbar.click_back_button ();
    }

    public void click_search_button () {
        if (window.ui_state == UIState.COLLECTION)
            collection_toolbar.click_search_button ();
    }

    public void pop_main_menu () {
        collection_toolbar.hamburger_btn.clicked ();
    }

    public string? _status;
    public string? status {
        get { return _status; }
        set {
            _status = value;
            display_toolbar.set_title (_status);
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

    public void setup_ui (AppWindow window) {
        this.window = window;

        var toolbar = window.display_page.toolbar;
        toolbar.bind_property ("title", display_toolbar, "title", BindingFlags.SYNC_CREATE);
        toolbar.bind_property ("subtitle", display_toolbar, "subtitle", BindingFlags.SYNC_CREATE);

        collection_toolbar.setup_ui (window);
        display_toolbar.setup_ui (window);
        status = _("Boxes");
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

        default:
            break;
        }
    }
}
