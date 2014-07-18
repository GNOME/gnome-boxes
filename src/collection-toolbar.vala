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
    private Image back_image;
    [GtkChild]
    private Button new_btn;

    private AppWindow window;

    construct {
        var back_icon = (get_direction () == TextDirection.RTL)? "go-previous-rtl-symbolic" :
                                                                 "go-previous-symbolic";
        back_image.set_from_icon_name (back_icon, IconSize.MENU);
    }

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

    public void click_back_button () {
        back_btn.clicked ();
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
            back_btn.show ();
            select_btn.hide ();
            search_btn.hide ();
            break;

        default:
            break;
        }
    }

}
