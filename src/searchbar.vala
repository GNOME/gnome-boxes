// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.Searchbar: Gtk.SearchBar {
    public bool enable_key_handler {
        set {
            if (value)
                GLib.SignalHandler.unblock (App.app.window, key_handler_id);
            else
                GLib.SignalHandler.block (App.app.window, key_handler_id);
        }
    }
    private Gtk.SearchEntry entry;

    private ulong key_handler_id;

    public Searchbar () {
        setup_searchbar ();

        key_handler_id = App.app.window.key_press_event.connect (on_app_key_pressed);
        entry.search_changed.connect (on_search_changed);
        entry.activate.connect ( () => {
            App.app.view.activate ();
        });

        notify["search-mode-enabled"].connect (() => {
            if (!search_mode_enabled)
                text = "";
        });
    }

    private void on_search_changed () {
        App.app.filter.text = text;
        App.app.view.refilter ();
    }

    public string text {
        get { return entry.text; }
        set { entry.set_text (value); }
    }

    private bool on_app_key_pressed (Gtk.Widget widget, Gdk.EventKey event) {
        if (App.app.ui_state != UIState.COLLECTION)
            return false;

        return handle_event ((Gdk.Event *) (&event));
    }

    private void setup_searchbar () {
        entry = new Gtk.SearchEntry ();
        entry.width_chars = 40;
        entry.hexpand = true;
        add (entry);

        show_all ();
    }
}
