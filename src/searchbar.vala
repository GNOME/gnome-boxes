// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/searchbar.ui")]
private class Boxes.Searchbar: Gtk.SearchBar {
    public bool enable_key_handler {
        set {
            if (value)
                GLib.SignalHandler.unblock (App.app.window, key_handler_id);
            else
                GLib.SignalHandler.block (App.app.window, key_handler_id);
        }
    }
    [GtkChild]
    private Gtk.SearchEntry entry;

    private ulong key_handler_id;

    public Searchbar () {
        search_mode_enabled = false;

        App.app.call_when_ready (on_app_ready);
    }

    [GtkCallback]
    private void on_search_changed () {
        App.app.filter.text = text;
        App.app.view.refilter ();
    }

    [GtkCallback]
    private void on_search_activated () {
        App.app.view.activate_first_item ();
    }

    [GtkCallback]
    private void on_search_mode_notify () {
        if (!search_mode_enabled)
            text = "";
    }

    public string text {
        get { return entry.text; }
        set { entry.set_text (value); }
    }

    private void on_app_ready () {
        key_handler_id = App.app.window.key_press_event.connect (on_app_key_pressed);
    }

    private bool on_app_key_pressed (Gtk.Widget widget, Gdk.EventKey event) {
        if (App.app.ui_state != UIState.COLLECTION)
            return false;

        return handle_event ((Gdk.Event) event);
    }
}
