// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/empty-boxes.ui")]
private class Boxes.EmptyBoxes : Gtk.Stack, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    [GtkChild]
    private Gtk.Box grid_box;

    private AppWindow window;

    construct {
        App.app.call_when_ready (on_app_ready);
    }

    public void setup_ui (AppWindow window) {
        this.window = window;
    }

    private void on_app_ready () {
        update_visibility ();

        App.app.collection.item_added.connect (update_visibility);
        App.app.collection.item_removed.connect (update_visibility);
    }

    private void update_visibility () {
        var visible = App.app.collection.length == 0;
        if (visible && visible_child != grid_box)
            visible_child = grid_box;

        if (ui_state != UIState.COLLECTION)
            return;

        if (visible)
            window.below_bin.set_visible_child_name ("empty-boxes");
        else
            window.below_bin.set_visible_child_name ("collection-stack");
    }
}
