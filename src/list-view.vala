// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/list-view.ui")]
private class Boxes.ListView: Gtk.ScrolledWindow {
    public CollectionFilter filter { get; protected set; }

    [GtkChild]
    private unowned Gtk.ListBox list_box;

    private Gtk.SizeGroup size_group;

    private HashTable<CollectionItem, ItemConnections> items_connections;

    private AppWindow window;
    private Boxes.ActionsPopover context_popover;

    private class ItemConnections: Object {
        private ulong categories_id;
        private ulong name_id;
        private ulong info_id;

        public weak ListView view { get; private set; }
        public Machine machine { get; private set; }

        public ItemConnections (ListView view, Machine machine) {
            this.view = view;
            this.machine = machine;

            categories_id = machine.config.notify["categories"].connect (() => {
                view.list_box.invalidate_sort ();
                view.list_box.invalidate_filter ();
            });
            name_id = machine.notify["name"].connect (() => {
                view.list_box.invalidate_sort ();
                view.list_box.invalidate_filter ();
            });
            info_id = machine.notify["info"].connect (() => {
                view.list_box.invalidate_sort ();
                view.list_box.invalidate_filter ();
            });
        }

        public override void dispose () {
            machine.config.disconnect (categories_id);
            machine.disconnect (name_id);
            machine.disconnect (info_id);
            base.dispose ();
        }
    }

    construct {
        items_connections = new HashTable<CollectionItem, ItemConnections> (direct_hash, direct_equal);

        size_group = new Gtk.SizeGroup (Gtk.SizeGroupMode.VERTICAL);
        filter = new CollectionFilter ();
        filter.notify["text"].connect (() => {
            list_box.invalidate_filter ();
        });
        setup_list_box ();
    }

    public void setup_ui (AppWindow window) {
        this.window = window;

        context_popover = new Boxes.ActionsPopover (window);
    }

    private void add_row (Gtk.Widget row) {
        var item = row as CollectionItem;
        var machine = item as Machine;

        items_connections[item] = new ItemConnections (this, machine);
    }

    private void remove_row (Gtk.Widget row) {
        var item = row as CollectionItem;
        items_connections.remove (item);

        size_group.remove_widget (row);
    }

    private void setup_list_box () {
        list_box.bind_model (App.app.collection.items, (item) => {
            var box_row = new Gtk.ListBoxRow ();
            size_group.add_widget (box_row);
            var view_row = new ListViewRow (item as CollectionItem);
            box_row.add (view_row);

            view_row.pop_context_menu.connect (() => {
                launch_context_popover_for_row (box_row);
            });

            box_row.visible = true;
            view_row.visible = true;

            return box_row;
        });
        list_box.set_filter_func (model_filter);

        var container = list_box as Gtk.Container;
        container.add.connect (add_row);
        container.remove.connect (remove_row);
    }



    private CollectionItem? get_item_for_row (Gtk.ListBoxRow box_row) {
        var view = box_row.get_child () as ListViewRow;
        if (view == null)
            return null;

        return view.item;
    }

    private bool model_filter (Gtk.ListBoxRow box_row) {
        var view = box_row.get_child () as ListViewRow;
        if (view  == null)
            return false;

        var item = view.item;
        if (item  == null)
            return false;

        return filter.filter (item as CollectionItem);
    }

    [GtkCallback]
    private void on_row_activated (Gtk.ListBoxRow row) {
        var item = get_item_for_row (row);
        if (item is LibvirtMachine) {
            var libvirt_machine = item as LibvirtMachine;
            if (libvirt_machine.importing)
                return;
        }

        window.select_item (item);
    }

    [GtkCallback]
    private bool on_button_press_event (Gdk.EventButton event) {
        if (event.type != Gdk.EventType.BUTTON_RELEASE)
            return false;

        if (event.button == 3)
            return on_button_3_press_event (event);

        return false;
    }

    private bool on_button_3_press_event (Gdk.EventButton event) {
        var box_row = list_box.get_row_at_y ((int) event.y);
        if (box_row == null)
            return false;

        return launch_context_popover_for_row (box_row);
    }

    [GtkCallback]
    private bool on_key_press_event (Gdk.EventKey event) {
        if (event.keyval != Gdk.Key.Menu)
            return false;

        var box_row = list_box.get_selected_row ();
        if (box_row == null)
            return false;

        return launch_context_popover_for_row (box_row);
    }

    private bool launch_context_popover_for_row (Gtk.ListBoxRow box_row) {
        var item = get_item_for_row (box_row);
        if (item == null)
            return false;

        var row = box_row.get_child () as Boxes.ListViewRow;
        context_popover.update_for_item (item);
        context_popover.relative_to = row.menu_button;
        context_popover.show ();

        return true;
    }
}
