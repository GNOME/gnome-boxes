// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/collection-toolbar.ui")]
private class Boxes.CollectionToolbar: HeaderBar {
    [GtkChild]
    private Button search_btn;
    [GtkChild]
    private Button select_btn;
    [GtkChild]
    private Button back_btn;
    [GtkChild]
    private Button new_btn;

    private AppWindow window;

    public void setup_ui (AppWindow window) {
        this.window = window;

        update_select_btn ();
        App.app.collection.item_added.connect (update_select_btn);
        App.app.collection.item_removed.connect (update_select_btn);

        update_search_btn ();
        App.app.collection.item_added.connect (update_search_btn);
        App.app.collection.item_removed.connect (update_search_btn);

        search_btn.bind_property ("active", window.searchbar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);

        window.notify["ui-state"].connect (ui_state_changed);
        App.app.notify["main-window"].connect (ui_state_changed);
    }

    public void click_back_button () {
        back_btn.clicked ();
    }

    public void click_new_button () {
        new_btn.clicked ();
    }

    public void click_search_button () {
        search_btn.clicked ();
    }

    [GtkCallback]
    private void on_new_btn_clicked () {
        window.set_state (UIState.WIZARD);
    }

    [GtkCallback]
    private void on_back_btn_clicked () {
        window.set_state (UIState.COLLECTION);
    }

    [GtkCallback]
    private void on_select_btn_clicked () {
        window.selection_mode = true;
    }

    private void update_search_btn () {
        search_btn.sensitive = App.app.collection.items.length != 0;
    }

    private void update_select_btn () {
        select_btn.sensitive = App.app.collection.items.length != 0;
    }

    private void ui_state_changed () {
        switch (window.ui_state) {
        case UIState.COLLECTION:
            back_btn.hide ();
            select_btn.show ();
            search_btn.show ();
            new_btn.show ();
            break;

        case UIState.CREDS:
            new_btn.hide ();
            back_btn.visible = (window == App.app.main_window);
            select_btn.hide ();
            search_btn.hide ();
            break;

        default:
            break;
        }
    }

}
