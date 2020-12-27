// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/collection-toolbar.ui")]
private class Boxes.CollectionToolbar: Hdy.HeaderBar {
    [GtkChild]
    private Button search_btn;
    [GtkChild]
    private Button select_btn;
    [GtkChild]
    private Button list_btn;
    [GtkChild]
    private Button grid_btn;
    [GtkChild]
    private Button back_btn;
    [GtkChild]
    private Button new_btn;
    [GtkChild]
    private MenuButton downloads_hub_btn;
    [GtkChild]
    public MenuButton hamburger_btn;

    private AppWindow window;

    public void setup_ui (AppWindow window) {
        this.window = window;

        update_select_btn ();
        App.app.collection.item_added.connect (update_select_btn);
        App.app.collection.item_removed.connect (update_select_btn);

        update_search_btn ();
        App.app.collection.item_added.connect (update_search_btn);
        App.app.collection.item_removed.connect (update_search_btn);

        var view_type = (AppWindow.ViewType) window.settings.get_enum ("view");
        update_view_type (view_type);

        search_btn.bind_property ("active", window.searchbar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);

        window.notify["ui-state"].connect (ui_state_changed);
        App.app.notify["main-window"].connect (ui_state_changed);

        var builder = new Builder.from_resource ("/org/gnome/Boxes/ui/menus.ui");
        MenuModel menu = (MenuModel) builder.get_object ("app-menu");
        hamburger_btn.popover = new Popover.from_model (hamburger_btn, menu);

        downloads_hub_btn.popover = DownloadsHub.get_default ();
    }

    public void click_back_button () {
        back_btn.clicked ();
    }

    public void click_search_button () {
        search_btn.clicked ();
    }

    [GtkCallback]
    private void on_new_btn_clicked () {
        window.show_vm_assistant ();
    }

    [GtkCallback]
    private void on_back_btn_clicked () {
        window.set_state (UIState.COLLECTION);
    }

    [GtkCallback]
    private void on_list_btn_clicked () {
        update_view_type (AppWindow.ViewType.LIST);
    }

    [GtkCallback]
    private void on_grid_btn_clicked () {
        update_view_type (AppWindow.ViewType.ICON);
    }

    [GtkCallback]
    private void on_select_btn_clicked () {
        window.selection_mode = true;
    }

    private void update_search_btn () {
        search_btn.sensitive = App.app.collection.length != 0;
    }

    private void update_select_btn () {
        select_btn.sensitive = App.app.collection.length != 0;
    }

    private void update_view_type (AppWindow.ViewType view_type) {
        window.view_type = view_type;
        window.settings.set_enum ("view", view_type);

        ui_state_changed ();
    }

    private void ui_state_changed () {
        switch (window.ui_state) {
        case UIState.COLLECTION:
            back_btn.hide ();
            select_btn.show ();
            search_btn.show ();
            new_btn.show ();
            grid_btn.visible = window.view_type != AppWindow.ViewType.ICON;
            list_btn.visible = window.view_type != AppWindow.ViewType.LIST;
            break;

        case UIState.CREDS:
            new_btn.hide ();
            back_btn.visible = (window == App.app.main_window);
            select_btn.hide ();
            search_btn.hide ();
            grid_btn.hide ();
            list_btn.hide ();
            break;

        default:
            break;
        }
    }

}
