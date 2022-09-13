// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/icon-view.ui")]
private class Boxes.IconView: Gtk.ScrolledWindow {
    [GtkChild]
    private unowned Gtk.FlowBox flowbox;

    private AppWindow window;
    private Boxes.ActionsPopover context_popover;

    construct {
        setup_flowbox ();
    }

    public void setup_ui (AppWindow window) {
        this.window = window;

        context_popover = new Boxes.ActionsPopover (window);
    }

    private void setup_flowbox () {
        flowbox.bind_model (App.app.collection.filtered_items, (item) => {
            var child = new Gtk.FlowBoxChild ();
            child.halign = Gtk.Align.START;
            var box = new IconViewChild (item as CollectionItem);
            child.add (box);

            box.visible = true;
            child.visible = true;

            return child;
        });
    }

    private CollectionItem? get_item_for_child (Gtk.FlowBoxChild child) {
        var view = child.get_child () as IconViewChild;
        if (view == null)
            return null;

        return view.item;
    }

    [GtkCallback]
    private void on_child_activated (Gtk.FlowBoxChild child) {
        var item = get_item_for_child (child);
        if (item is LibvirtMachine) {
            var machine = item as LibvirtMachine;
            if (machine.importing)
                return;
        }

        window.select_item (item);
    }

    [GtkCallback]
    private bool on_button_press_event (Gdk.EventButton event) {
        if (event.type != Gdk.EventType.BUTTON_RELEASE || event.button != 3)
            return false;

        var child = flowbox.get_child_at_pos ((int) event.x, (int) event.y);
        if (child == null)
            return false;

        return launch_context_popover_for_child (child);
    }

    [GtkCallback]
    private bool on_key_press_event (Gdk.EventKey event) {
        if (event.keyval != Gdk.Key.Menu)
            return false;

        var child = flowbox.get_selected_children ().nth_data (0);
        if (child == null)
            return false;

        return launch_context_popover_for_child (child);
    }

    private bool launch_context_popover_for_child (Gtk.FlowBoxChild child) {
        var item = get_item_for_child (child);
        if (item == null)
            return false;

        var icon_view_child = child.get_child () as IconViewChild;
        var thumbnail = icon_view_child.thumbnail;

        context_popover.update_for_item (item);
        context_popover.set_relative_to (thumbnail.get_parent ());
        context_popover.show ();

        return true;
    }
}
