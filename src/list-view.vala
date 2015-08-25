// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/list-view.ui")]
private class Boxes.ListView: Gtk.ScrolledWindow, Boxes.ICollectionView, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    public CollectionFilter filter { get; protected set; }

    [GtkChild]
    private Gtk.ListBox list_box;

    private GLib.List<CollectionItem> hidden_items;
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
        hidden_items = new GLib.List<CollectionItem> ();
        items_connections = new HashTable<CollectionItem, ItemConnections> (direct_hash, direct_equal);

        setup_list_box ();

        filter = new CollectionFilter ();
        filter.notify["text"].connect (() => {
            list_box.invalidate_filter ();
        });
        filter.filter_func_changed.connect (() => {
            list_box.invalidate_filter ();
        });

        notify["ui-state"].connect (ui_state_changed);
    }

    public void setup_ui (AppWindow window) {
        this.window = window;

        window.notify["selection-mode"].connect (() => {
            list_box.selection_mode = window.selection_mode ? Gtk.SelectionMode.MULTIPLE :
                                                              Gtk.SelectionMode.NONE;

            update_selection_mode ();
        });

        context_popover = new Boxes.ActionsPopover (window);
    }

    public void add_item (CollectionItem item) {
        var machine = item as Machine;

        if (machine == null) {
            warning ("Cannot add item %p".printf (&item));

            return;
        }

        var window = machine.window;
        if (window.ui_state == UIState.WIZARD) {
            // Don't show newly created items until user is out of wizard
            hidden_items.append (item);

            ulong ui_state_id = 0;

            ui_state_id = window.notify["ui-state"].connect (() => {
                if (window.ui_state == UIState.WIZARD)
                    return;

                if (hidden_items.find (item) != null) {
                    add_item (item);
                    hidden_items.remove (item);
                }
                window.disconnect (ui_state_id);
            });

            return;
        }

        add_row (item);
        items_connections[item] = new ItemConnections (this, machine);

        item.set_state (window.ui_state);
    }

    private void add_row (CollectionItem item) {
        var box_row = new Gtk.ListBoxRow ();
        var view_row = new ListViewRow (item);

        view_row.notify["selected"].connect (() => {
            propagate_view_row_selection (view_row);
        });

        box_row.visible = true;
        view_row.visible = true;

        box_row.add (view_row);
        list_box.add (box_row);
    }

    public void remove_item (CollectionItem item) {
        hidden_items.remove (item);
        items_connections.remove (item);
        remove_row (item);
    }

    private void remove_row (CollectionItem item) {
        foreach_row ((box_row) => {
            var view_row = box_row.get_child () as ListViewRow;
            if (view_row == null)
                return;

            if (view_row.item == item)
                list_box.remove (box_row);
        });
    }

    public void select_by_criteria (SelectionCriteria criteria) {
        window.selection_mode = true;

        switch (criteria) {
        default:
        case SelectionCriteria.ALL:
            foreach_row ((box_row) => { select_row (box_row); });

            break;
        case SelectionCriteria.NONE:
            foreach_row ((box_row) => { unselect_row (box_row); });

            break;
        case SelectionCriteria.RUNNING:
            foreach_row ((box_row) => {
                var item = get_item_for_row (box_row);
                if (item != null && item is Machine && (item as Machine).is_running)
                    select_row (box_row);
                else
                    unselect_row (box_row);
            });

            break;
        }

        App.app.notify_property ("selected-items");
    }

    public List<CollectionItem> get_selected_items () {
        var selected = new List<CollectionItem> ();

        foreach (var box_row in list_box.get_selected_rows ()) {
            var item = get_item_for_row (box_row);
            selected.append (item);
        }

        return (owned) selected;
    }

    public void activate_first_item () {
        Gtk.ListBoxRow first_row = null;
        foreach_row ((box_row) => {
            if (first_row == null)
                first_row = box_row;
        });

        if (first_row == null)
            list_box.row_activated (first_row);
    }

    private void setup_list_box () {
        list_box.selection_mode = Gtk.SelectionMode.NONE;
        list_box.set_sort_func (model_sort);
        list_box.set_filter_func (model_filter);

        list_box.row_activated.connect ((box_row) => {
            if (window.selection_mode)
                return;

            var item = get_item_for_row (box_row);
            if (item is LibvirtMachine && (item as LibvirtMachine).importing)
                return;

            window.select_item (item);
        });

        update_selection_mode ();
    }

    private CollectionItem? get_item_for_row (Gtk.ListBoxRow box_row) {
        var view = box_row.get_child () as ListViewRow;
        if (view == null)
            return null;

        return view.item;
    }

    private void foreach_row (Func<Gtk.ListBoxRow> func) {
        list_box.forall ((child) => {
            var box_row = child as Gtk.ListBoxRow;
            if (box_row == null)
                return;

            func (box_row);
        });
    }

    private int model_sort (Gtk.ListBoxRow box_row1, Gtk.ListBoxRow box_row2) {
        var view_row1 = box_row1.get_child () as ListViewRow;
        var view_row2 = box_row2.get_child () as ListViewRow;
        var item1 = view_row1.item;
        var item2 = view_row2.item;

        if (item1 == null || item2 == null)
            return 0;

        return item1.compare (item2);
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

    private void ui_state_changed () {
        if (ui_state == UIState.COLLECTION)
            list_box.unselect_all ();
    }

    [GtkCallback]
    private bool on_button_press_event (Gdk.EventButton event) {
        if (event.type != Gdk.EventType.BUTTON_RELEASE)
            return false;

        switch (event.button) {
        case 1:
            return on_button_1_press_event (event);
        case 3:
            return on_button_3_press_event (event);
        default:
            return false;
        }
    }

    private bool on_button_1_press_event (Gdk.EventButton event) {
        if (!window.selection_mode)
            return false;

        // Necessary to avoid treating an event from a child widget which would mess with getting the correct row.
        if (event.window != list_box.get_window ())
            return false;

        var box_row = list_box.get_row_at_y ((int) event.y);
        if (box_row == null)
            return false;

        toggle_row_selected (box_row);

        return true;
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

        context_popover.update_for_item (item);
        context_popover.relative_to = box_row;
        context_popover.show ();

        return true;
    }

    private void update_selection_mode () {
        foreach_row ((box_row) => {
            var view_row = box_row.get_child () as ListViewRow;

            if (view_row.selection_mode != window.selection_mode)
                view_row.selection_mode = window.selection_mode;

            unselect_row (box_row);
        });
    }

    private void propagate_view_row_selection (ListViewRow view_row) {
        var box_row = view_row.parent as Gtk.ListBoxRow;

        if (view_row.selected)
            select_row (box_row);
        else
            unselect_row (box_row);
    }

    private void toggle_row_selected (Gtk.ListBoxRow box_row) {
        var view_row = box_row.get_child () as ListViewRow;

        if (view_row.selected)
            unselect_row (box_row);
        else
            select_row (box_row);
    }

    private void select_row (Gtk.ListBoxRow box_row) {
        var view_row = box_row.get_child () as ListViewRow;

        list_box.select_row (box_row);
        if (!view_row.selected)
            view_row.selected = true;

        App.app.notify_property ("selected-items");
    }

    private void unselect_row (Gtk.ListBoxRow box_row) {
        var view_row = box_row.get_child () as ListViewRow;

        list_box.unselect_row (box_row);
        if (view_row.selected)
            view_row.selected = false;

        App.app.notify_property ("selected-items");
    }
}
