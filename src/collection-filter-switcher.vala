// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/collection-filter-switcher.ui")]
private class Boxes.CollectionFilterSwitcher: Gtk.ButtonBox {
    [GtkChild]
    private Gtk.ToggleButton all_button;
    [GtkChild]
    private Gtk.ToggleButton favorites_button;

    private Gtk.ToggleButton active_button;
    private weak AppWindow window;

    public void setup_ui (AppWindow window) {
        this.window = window;
        assert (window != null);

        all_button.active = true;
        activate_button (all_button);
        App.app.call_when_ready (on_app_ready);
    }

    private CollectionFilterView.FilterType get_filter_type () {
        if (active_button == all_button)
            return CollectionFilterView.FilterType.ALL;
        if (active_button == favorites_button)
            return CollectionFilterView.FilterType.FAVORITES;
        else
            return CollectionFilterView.FilterType.ALL;
    }

    private void on_app_ready () {
        update_sensitivity ();

        App.app.collection.item_added.connect (update_sensitivity);
        App.app.collection.item_removed.connect (update_sensitivity);
    }

    private void update_sensitivity () {
        sensitive = (App.app.collection.length != 0);
    }

    [GtkCallback]
    private void activate_button (Gtk.ToggleButton button) {
        if (button == active_button)
            return;

        if (button.active)
            active_button = button;

        foreach (var child in get_children ()) {
            var toggle_button = child as Gtk.ToggleButton;
            if (toggle_button != null)
                toggle_button.active = toggle_button == active_button;
        }

        window.set_filter_type (get_filter_type ());
    }
}
