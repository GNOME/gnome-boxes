// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;

private class Boxes.CollectionView: Boxes.UI {
    public override Clutter.Actor actor { get { return gtkactor; } }

    private GtkClutter.Actor gtkactor;

    private Category _category;
    public Category category {
        get { return _category; }
        set {
            _category = value;
            // FIXME: update view
        }
    }

    private Gtk.IconView icon_view;
    private enum ModelColumns {
        SCREENSHOT,
        TITLE,
        ITEM
    }
    private Gtk.ListStore model;

    public bool visible {
        set { icon_view.visible = value; }
    }

    public CollectionView () {
        category = new Category (_("New and Recent"), Category.Kind.NEW);
        setup_view ();
        App.app.notify["selection-mode"].connect (() => {
            var mode = App.app.selection_mode ? Gtk.SelectionMode.MULTIPLE : Gtk.SelectionMode.NONE;
            icon_view.set_selection_mode (mode);
        });
    }

    private void get_item_pos (CollectionItem item, out float x, out float y) {
        Gdk.Rectangle rect;
        var path = get_path_for_item (item);
        icon_view.get_cell_rect (path, null, out rect);
        x = rect.x;
        y = rect.y;
    }

    public override void ui_state_changed () {
        uint opacity = 0;
        var current_item = App.app.current_item;
        switch (ui_state) {
        case UIState.COLLECTION:
            opacity = 255;
            icon_view.unselect_all ();
            if (current_item != null) {
                var actor = current_item.actor;
                actor.set_easing_duration (0);
                actor.show ();

                App.app.overlay_bin.set_alignment (actor,
                                                   Clutter.BinAlignment.FIXED,
                                                   Clutter.BinAlignment.FIXED);
                float item_x, item_y;
                get_item_pos (current_item, out item_x, out item_y);
                actor.x = item_x;
                actor.y = item_y;
                actor.min_width = actor.natural_width = Machine.SCREENSHOT_WIDTH;

                actor.set_easing_duration (App.app.duration);
                var id = icon_view.size_allocate.connect ((allocation) => {
                    Idle.add_full (Priority.HIGH, () => {
                        float item_x2, item_y2;
                        get_item_pos (current_item, out item_x2, out item_y2);
                        actor.x = item_x2;
                        actor.y = item_y2;
                        return false;
                    });
                });
                ulong completed_id = 0;
                completed_id = actor.transitions_completed.connect (() => {
                    actor.disconnect (completed_id);
                    icon_view.disconnect (id);
                    if (App.app.ui_state == UIState.COLLECTION ||
                        App.app.current_item.actor != actor)
                        actor_remove (actor);
                });
            }
            break;

        case UIState.CREDS:
            var actor = current_item.actor;
            if (actor.get_parent () == null) {
                App.app.overlay_bin.add (actor,
                                         Clutter.BinAlignment.FIXED,
                                         Clutter.BinAlignment.FIXED);
                actor.set_easing_mode (Clutter.AnimationMode.LINEAR);

                float item_x, item_y;
                get_item_pos (current_item, out item_x, out item_y);
                Clutter.ActorBox box = { item_x, item_y, item_x + Machine.SCREENSHOT_WIDTH, item_y + Machine.SCREENSHOT_HEIGHT * 2};
                actor.allocate (box, 0);

            }
            actor.min_width = actor.natural_width = Machine.SCREENSHOT_WIDTH * 2;
            App.app.overlay_bin.set_alignment (actor,
                                               Clutter.BinAlignment.CENTER,
                                               Clutter.BinAlignment.CENTER);
            actor.set_easing_duration (App.app.duration);
            break;

        case UIState.WIZARD:
            if (current_item != null)
                actor_remove (current_item.actor);
            break;

        case UIState.PROPERTIES:
            current_item.actor.hide ();
            break;
        }

        fade_actor (actor, opacity);

        if (current_item != null)
            current_item.ui_state = ui_state;
    }

    public void update_item_visible (CollectionItem item) {
        var visible = false;

        // FIXME
        if (item is Machine) {
            var machine = item as Machine;

            switch (category.kind) {
            case Category.Kind.USER:
                visible = category.name in machine.config.categories;
                break;
            case Category.Kind.NEW:
                visible = true;
                break;
            }
        }

        item.actor.visible = visible;
    }

    private Gtk.TreeIter append (Gdk.Pixbuf pixbuf,
                                 string title,
                                 CollectionItem item)
    {
        Gtk.TreeIter iter;

        model.append (out iter);
        model.set (iter, ModelColumns.SCREENSHOT, pixbuf);
        model.set (iter, ModelColumns.TITLE, title);
        model.set (iter, ModelColumns.ITEM, item);

        item.set_data<Gtk.TreeIter?> ("iter", iter);

        return iter;
    }

    public void add_item (CollectionItem item) {
        var machine = item as Machine;

        if (machine == null) {
            warning ("Cannot add item %p".printf (&item));
            return;
        }

        var iter = append (machine.pixbuf, item.title, item);
        var pixbuf_id = machine.notify["pixbuf"].connect (() => {
            // apparently iter is stable after insertion/removal/sort
            model.set (iter, ModelColumns.SCREENSHOT, machine.pixbuf);
        });
        item.set_data<ulong> ("pixbuf_id", pixbuf_id);

        item.ui_state = UIState.COLLECTION;
        actor_remove (item.actor);

        update_item_visible (item);
    }

    public List<CollectionItem> get_selected_items () {
        var list = new List<CollectionItem> ();
        var selected = icon_view.get_selected_items ();

        foreach (var path in selected)
            list.append (get_item_for_path (path));

        return list;
    }

    public void remove_item (CollectionItem item) {
        var iter = item.get_data<Gtk.TreeIter?> ("iter");
        var pixbuf_id = item.get_data<ulong> ("pixbuf_id");

        if (iter == null) {
            debug ("item not in view or already removed");
            return;
        }

        model.remove (iter);
        item.set_data<Gtk.TreeIter?> ("iter", null);
        item.disconnect (pixbuf_id);
    }

    private Gtk.TreePath get_path_for_item (CollectionItem item) {
        var iter = item.get_data<Gtk.TreeIter?> ("iter");
        return model.get_path (iter);
    }

    private CollectionItem get_item_for_path (Gtk.TreePath path) {
        Gtk.TreeIter iter;
        GLib.Value value;

        model.get_iter (out iter, path);
        model.get_value (iter, ModelColumns.ITEM, out value);

        return (CollectionItem) value;
    }

    private void setup_view () {
        model = new Gtk.ListStore (3,
                                   typeof (Gdk.Pixbuf),
                                   typeof (string),
                                   typeof (CollectionItem));
        model.set_default_sort_func ((model, a, b) => {
            CollectionItem item_a, item_b;

            model.get (a, ModelColumns.ITEM, out item_a);
            model.get (b, ModelColumns.ITEM, out item_b);

            if (item_a == null || item_b == null) // FIXME?!
                return 0;

            return item_a.title.collate (item_b.title);
        });
        model.set_sort_column_id (Gtk.SortColumn.DEFAULT, Gtk.SortType.ASCENDING);

        icon_view = new Gtk.IconView.with_model (model);
        icon_view.get_style_context ().add_class ("boxes-bg");
        icon_view.button_press_event.connect ((event) => {
            if (App.app.selection_mode)
                event.state |= icon_view.get_modifier_mask (Gdk.ModifierIntent.MODIFY_SELECTION);

            return false;
        });
        icon_view.item_width = 185;
        icon_view.column_spacing = 20;
        icon_view.margin = 16;
        icon_view_activate_on_single_click (icon_view, true);
        icon_view.set_selection_mode (Gtk.SelectionMode.NONE);
        icon_view.item_activated.connect ((view, path) => {
            var item = get_item_for_path (path);
            App.app.select_item (item);
        });
        icon_view.selection_changed.connect (() => {
            App.app.notify_property ("selected-items");
        });
        var pixbuf_renderer = new Gtk.CellRendererPixbuf ();
        pixbuf_renderer.xalign = 0.5f;
        pixbuf_renderer.yalign = 0.5f;
        icon_view.pack_start (pixbuf_renderer, false);
        icon_view.add_attribute (pixbuf_renderer, "pixbuf", ModelColumns.SCREENSHOT);

        var text_renderer = new Gtk.CellRendererText ();
        text_renderer.xalign = 0.5f;
        text_renderer.foreground = "white";
        icon_view.pack_start (text_renderer, false);
        icon_view.add_attribute(text_renderer, "text", ModelColumns.TITLE);

        var scrolled_window = new Gtk.ScrolledWindow (null, null);
        // TODO: this should be set, but doesn't resize correctly the gtkactor..
        //        scrolled_window.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scrolled_window.add (icon_view);
        scrolled_window.show_all ();

        gtkactor = new GtkClutter.Actor.with_contents (scrolled_window);
        gtkactor.name = "collection-view";
    }
}
