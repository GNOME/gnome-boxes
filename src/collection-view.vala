// This file is part of GNOME Boxes. License: LGPLv2+

public enum Boxes.SelectionCriteria {
    ALL,
    NONE,
    RUNNING
}

private class Boxes.CollectionView: Gd.MainView, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private AppWindow window;

    private Category _category;
    public Category category {
        get { return _category; }
        set {
            _category = value;
            // FIXME: update view
        }
    }

    private enum ModelColumns {
        SCREENSHOT = Gd.MainColumns.ICON,
        TITLE = Gd.MainColumns.PRIMARY_TEXT,
        INFO = Gd.MainColumns.SECONDARY_TEXT,
        SELECTED = Gd.MainColumns.SELECTED,
        PULSE = Gd.MainColumns.PULSE,
        ITEM = Gd.MainColumns.LAST,

        LAST
    }

    private Gtk.ListStore store;
    private Gtk.TreeModelFilter model_filter;
    private Boxes.ActionsPopover context_popover;

    construct {
        category = new Category (_("New and Recent"), Category.Kind.NEW);
        setup_view ();
        notify["ui-state"].connect (ui_state_changed);
    }

    public void setup_ui (AppWindow window) {
        this.window = window;

        window.notify["selection-mode"].connect (() => {
            set_selection_mode (window.selection_mode);
            if (!window.selection_mode)
                unselect_all (); // Reset selection on exiting selection mode
        });

        var icon_view = get_generic_view () as Gtk.IconView;
        icon_view.button_release_event.connect (on_button_press_event);
        icon_view.key_press_event.connect (on_key_press_event);
        context_popover = new Boxes.ActionsPopover (window);
        context_popover.relative_to = icon_view;
    }

    private void ui_state_changed () {
        if (ui_state == UIState.COLLECTION)
            unselect_all ();
    }

    private void update_screenshot (Gtk.TreeIter iter) {
        CollectionItem item;
        GLib.Icon[] emblem_icons = {};

        store.get (iter, ModelColumns.ITEM, out item);
        Machine machine = item as Machine;
        return_if_fail (machine != null);
        var pixbuf = machine.pixbuf;

        if ("favorite" in machine.config.categories)
            emblem_icons += create_symbolic_emblem ("emblem-favorite");

        if (emblem_icons.length > 0) {
            var emblemed_icon = new GLib.EmblemedIcon (pixbuf, null);
            foreach (var emblem_icon in emblem_icons)
                emblemed_icon.add_emblem (new GLib.Emblem (emblem_icon));

            var theme = Gtk.IconTheme.get_default ();

            try {
                var size = int.max (pixbuf.width, pixbuf.height);
                var icon_info = theme.lookup_by_gicon (emblemed_icon, size,
                                                       Gtk.IconLookupFlags.FORCE_SIZE);
                pixbuf = icon_info.load_icon ();
            } catch (GLib.Error error) {
                warning ("Unable to render the emblem: " + error.message);
            }
        }

        store.set (iter, ModelColumns.SCREENSHOT, pixbuf);
        queue_draw ();
    }

    private Gtk.TreeIter append (string title,
                                 string? info,
                                 CollectionItem item) {
        Gtk.TreeIter iter;

        store.append (out iter);
        store.set (iter, Gd.MainColumns.ID, "%p".printf (item));
        store.set (iter, ModelColumns.TITLE, title);
        if (info != null)
            store.set (iter, ModelColumns.INFO, info);
        store.set (iter, ModelColumns.SELECTED, false);
        store.set (iter, ModelColumns.ITEM, item);
        update_screenshot (iter);

        item.set_data<Gtk.TreeIter?> ("iter", iter);

        return iter;
    }

    public void add_item (CollectionItem item) {
        var machine = item as Machine;

        if (machine == null) {
            warning ("Cannot add item %p".printf (&item));
            return;
        }

        var iter = append (machine.name, machine.info,  item);
        var pixbuf_id = machine.notify["pixbuf"].connect (() => {
            // apparently iter is stable after insertion/removal/sort
            update_screenshot (iter);
        });
        item.set_data<ulong> ("pixbuf_id", pixbuf_id);

        var categories_id = machine.config.notify["categories"].connect (() => {
            // apparently iter is stable after insertion/removal/sort
            update_screenshot (iter);
        });
        item.set_data<ulong> ("categories_id", categories_id);

        var name_id = item.notify["name"].connect (() => {
            // apparently iter is stable after insertion/removal/sort
            store.set (iter, ModelColumns.TITLE, item.name);
            queue_draw ();
        });
        item.set_data<ulong> ("name_id", name_id);

        var info_id = machine.notify["info"].connect (() => {
            // apparently iter is stable after insertion/removal/sort
            store.set (iter, ModelColumns.INFO, machine.info);
            queue_draw ();
        });
        item.set_data<ulong> ("info_id", info_id);

        setup_activity (iter, machine);
        var under_construct_id = machine.notify["under-construction"].connect (() => {
            // apparently iter is stable after insertion/removal/sort
            setup_activity (iter, machine);
            queue_draw ();
        });
        item.set_data<ulong> ("under_construct_id", under_construct_id);
        var machine_state_id = machine.notify["state"].connect (() => {
            // apparently iter is stable after insertion/removal/sort
            setup_activity (iter, machine);
            queue_draw ();
        });
        item.set_data<ulong> ("machine_state_id", machine_state_id);

        item.set_state (window.ui_state);
    }

    public List<CollectionItem> get_selected_items () {
        var selected = new List<CollectionItem> ();

        store.foreach ((store, path, iter) => {
            CollectionItem item;
            bool is_selected;

            store.get (iter,
                       ModelColumns.SELECTED, out is_selected,
                       ModelColumns.ITEM, out item);
            if (is_selected && item != null)
                selected.append (item);

            return false;
        });

        return (owned) selected;
    }

    public void remove_item (CollectionItem item) {
        var iter = item.get_data<Gtk.TreeIter?> ("iter");
        if (iter == null) {
            debug ("item not in view or already removed");
            return;
        }

        store.remove (iter);
        item.set_data<Gtk.TreeIter?> ("iter", null);

        var pixbuf_id = item.get_data<ulong> ("pixbuf_id");
        item.disconnect (pixbuf_id);
        var name_id = item.get_data<ulong> ("name_id");
        item.disconnect (name_id);
        var info_id = item.get_data<ulong> ("info_id");
        item.disconnect (info_id);
        var under_construct_id = item.get_data<ulong> ("under_construct_id");
        item.disconnect (under_construct_id);
        var machine_state_id = item.get_data<ulong> ("machine_state_id");
        if (machine_state_id != 0)
            item.disconnect (machine_state_id);

        if (item as Machine != null) {
            var machine = item as Machine;
            var categories_id = item.get_data<ulong> ("categories_id");
            machine.config.disconnect (categories_id);
        }
    }

    private CollectionItem get_item_for_iter (Gtk.TreeIter iter) {
        GLib.Value value;

        store.get_value (iter, ModelColumns.ITEM, out value);

        return (CollectionItem) value;
    }


    private CollectionItem get_item_for_path (Gtk.TreePath path) {
        Gtk.TreeIter filter_iter, iter;

        model_filter.get_iter (out filter_iter, path);
        model_filter.convert_iter_to_child_iter (out iter, filter_iter);

        return get_item_for_iter (iter);
    }

    private bool model_visible (Gtk.TreeModel model, Gtk.TreeIter iter) {
        var item = get_item_for_iter (iter);
        if (item  == null)
            return false;

        return App.app.filter.filter (item);
    }

    public void refilter () {
        model_filter.refilter ();
    }

    public void activate_first_item () {
        if (model_filter.iter_n_children (null) == 1) {
            Gtk.TreePath path = new Gtk.TreePath.from_string ("0");
            (get_generic_view () as Gtk.IconView).item_activated (path);
        }
    }

    private void setup_view () {
        store = new Gtk.ListStore (ModelColumns.LAST,
                                   typeof (string),
                                   typeof (string),
                                   typeof (string),
                                   typeof (string),
                                   typeof (Gdk.Pixbuf),
                                   typeof (long),
                                   typeof (bool),
                                   typeof (uint),
                                   typeof (CollectionItem));
        store.set_default_sort_func ((store, a, b) => {
            CollectionItem item_a, item_b;

            store.get (a, ModelColumns.ITEM, out item_a);
            store.get (b, ModelColumns.ITEM, out item_b);

            if (item_a == null || item_b == null) // FIXME?!
                return 0;

            return item_a.compare (item_b);
        });
        store.set_sort_column_id (Gtk.SortColumn.DEFAULT, Gtk.SortType.ASCENDING);
        store.row_deleted.connect (() => {
            App.app.notify_property ("selected-items");
        });
        store.row_inserted.connect (() => {
            App.app.notify_property ("selected-items");
        });

        model_filter = new Gtk.TreeModelFilter (store, null);
        model_filter.set_visible_func (model_visible);

        set_view_type (Gd.MainViewType.ICON);
        set_model (model_filter);
        get_style_context ().add_class ("content-bg");
        item_activated.connect ((view, id, path) => {
            var item = get_item_for_path (path);
            if (item is LibvirtMachine && (item as LibvirtMachine).importing)
                return;
            window.select_item (item);
        });
        view_selection_changed.connect (() => {
            queue_draw ();
            App.app.notify_property ("selected-items");
        });

        show_all ();
    }

    public void select (SelectionCriteria selection) {
        window.selection_mode = true;

        model_filter.foreach ( (filter_model, filter_path, filter_iter) => {
            Gtk.TreeIter iter;
            model_filter.convert_iter_to_child_iter (out iter, filter_iter);
            bool selected;
            switch (selection) {
            default:
            case SelectionCriteria.ALL:
                selected = true;
                break;
            case SelectionCriteria.NONE:
                selected = false;
                break;
            case SelectionCriteria.RUNNING:
                CollectionItem item;
                store.get (iter, ModelColumns.ITEM, out item);
                selected = item != null && item is Machine &&
                    (item as Machine).is_running ();
                break;
            }
            store.set (iter, ModelColumns.SELECTED, selected);
            return false;
        });
        queue_draw ();
        App.app.notify_property ("selected-items");
    }

    private void setup_activity (Gtk.TreeIter iter, Machine machine) {
        var activity_timeout = machine.get_data<uint> ("activity_timeout");
        if (activity_timeout > 0) {
            Source.remove (activity_timeout);
            machine.set_data<uint> ("activity_timeout", 0);
        }

        if (!machine.under_construction) {
            store.set (iter, ModelColumns.PULSE, 0);
            var machine_state_id = machine.get_data<ulong> ("machine_state_id");
            if (machine_state_id != 0) {
                machine.disconnect (machine_state_id);
                machine.set_data<ulong> ("machine_state_id", 0);
            }

            return;
        }

        var pulse = 1;
        store.set (iter, ModelColumns.PULSE, pulse++);

        if (machine.state == Machine.MachineState.SAVED)
            return;

        activity_timeout = Timeout.add (150, () => {
            var machine_iter = machine.get_data<Gtk.TreeIter?> ("iter");
            if (machine_iter == null)
                return false; // Item removed

            store.set (machine_iter, ModelColumns.PULSE, pulse++);
            queue_draw ();

            return true;
        });
        machine.set_data<uint> ("activity_timeout", activity_timeout);
    }

    private bool on_button_press_event (Gdk.EventButton event) {
        if (event.type != Gdk.EventType.BUTTON_RELEASE || event.button != 3)
            return false;

        var generic_view = get_generic_view () as Gd.MainViewGeneric;
        var path = generic_view.get_path_at_pos ((int) event.x, (int) event.y);
        if (path == null)
            return false;

        return launch_context_popover_for_path (path);
    }

    private bool on_key_press_event (Gdk.EventKey event) {
        if (event.keyval != Gdk.Key.Menu)
            return false;

        var icon_view = get_generic_view () as Gtk.IconView;
        Gtk.TreePath path;
        Gtk.CellRenderer cell;
        if (!icon_view.get_cursor (out path, out cell))
            return false;

        return launch_context_popover_for_path (path);
    }

    private bool launch_context_popover_for_path (Gtk.TreePath path) {
        var item = get_item_for_path (path);
        if (item == null)
            return false;

        var icon_view = get_generic_view () as Gtk.IconView;
        Gdk.Rectangle rect;
        icon_view.get_cell_rect (path, null, out rect);

        context_popover.update_for_item (item);
        var rectangle = Cairo.RectangleInt () { x = rect.x,
                                                y = rect.y,
                                                width = rect.width,
                                                height = rect.height / 2}; // Show in the middle
        context_popover.pointing_to = rectangle;
        context_popover.show ();

        return true;
    }
}
