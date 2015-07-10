// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/collection-filter-switcher.ui")]
private class Boxes.CollectionFilterSwitcher: Gtk.ButtonBox {
    [GtkChild]
    private Gtk.ToggleButton all_button;
    [GtkChild]
    private Gtk.ToggleButton local_button;
    [GtkChild]
    private Gtk.ToggleButton remote_button;

    private Gtk.ToggleButton active_button;
    private weak AppWindow window;

    public void setup_ui (AppWindow window) {
        this.window = window;
        assert (window != null);

        all_button.active = true;
        activate_button (all_button);

        window.foreach_view ((view) => { view.filter.filter_func = null; });
    }

    private unowned CollectionFilterFunc? get_filter_func () {
        if (active_button == all_button)
            return null;
        if (active_button == local_button)
            return local_filter_func;
        if (active_button == remote_button)
            return remote_filter_func;
        else
            return null;
    }

    private bool local_filter_func (Boxes.CollectionItem item) {
        return (item is Machine) && (item as Machine).is_local;
    }

    private bool remote_filter_func (Boxes.CollectionItem item) {
        return (item is Machine) && !(item as Machine).is_local;
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

        window.foreach_view ((view) => { view.filter.filter_func = get_filter_func (); });
    }
}
