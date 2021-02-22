// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/list-view.ui")]
private class Boxes.ListView: Gtk.ScrolledWindow, Boxes.ICollectionView, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

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
                assert (item != null);

                if (item != null && item is Machine) {
                    var machine = item as Machine;
                    if (machine.is_running)
                        select_row (box_row);
                } else
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
        list_box.bind_model (App.app.collection.items, (item) => {
            var box_row = new Gtk.ListBoxRow ();
            size_group.add_widget (box_row);
            var view_row = new ListViewRow (item as CollectionItem);
            box_row.add (view_row);

            view_row.notify["selected"].connect (() => {
                propagate_view_row_selection (view_row);
            });

            box_row.visible = true;
            view_row.visible = true;

            return box_row;
        });
        list_box.selection_mode = Gtk.SelectionMode.NONE;
        list_box.set_filter_func (model_filter);

        list_box.row_activated.connect ((box_row) => {
            if (window.selection_mode)
                return;

            var item = get_item_for_row (box_row);
            if (item is LibvirtMachine) {
                var libvirt_machine = item as LibvirtMachine;
                if (libvirt_machine.importing)
                    return;
            }

            window.select_item (item);
        });

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

    private void foreach_row (Func<Gtk.ListBoxRow> func) {
        list_box.forall ((child) => {
            var box_row = child as Gtk.ListBoxRow;
            if (box_row == null)
                return;

            func (box_row);
        });
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

    public void select_all () {
        list_box.select_all ();

        foreach_row (select_row);

        App.app.notify_property ("selected-items");
    }

    public void unselect_all () {
        list_box.unselect_all ();

        foreach_row (unselect_row);

        App.app.notify_property ("selected-items");
    }

    [GtkCallback]
    private void on_size_allocate (Gtk.Allocation allocation) {
        // Work around for https://gitlab.gnome.org/GNOME/gnome-boxes/issues/76
        bool small_screen = (allocation.width < max_content_width);

        if (small_screen) {
            list_box.halign = Gtk.Align.FILL;
            list_box.set_size_request (-1, -1);
        } else {
            list_box.halign = Gtk.Align.CENTER;
            // 100 here should cover margins, padding, and theme specifics.
            list_box.set_size_request (max_content_width - 100, -1);
        }
    }
}
