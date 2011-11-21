// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;

private class Boxes.CollectionView: Boxes.UI {
    public override Clutter.Actor actor { get { return gtkactor; } }

    private App app;
    private GtkClutter.Actor gtkactor;
    private Clutter.Box over_boxes; // a box on top of boxes list

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

    public CollectionView (App app, Category category) {
        this.app = app;
        this.category = category;

        setup_view ();
        app.notify["selection-mode"].connect (() => {
            var mode = app.selection_mode ? Gtk.SelectionMode.MULTIPLE : Gtk.SelectionMode.SINGLE;
            icon_view.set_selection_mode (mode);
        });
    }

    public void set_over_boxes (Clutter.Actor actor, bool center = false) {
        if (center)
            over_boxes.pack (actor,
                             "x-align", Clutter.BinAlignment.CENTER,
                             "y-align", Clutter.BinAlignment.CENTER);
        else
            over_boxes.pack (actor);

        actor_add (over_boxes, app.stage);
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.COLLECTION:
            actor.show ();
            icon_view.unselect_all ();
            actor_remove (app.wizard.actor);
            actor_remove (over_boxes);
            if (app.current_item != null)
                actor_remove (app.current_item.actor);
            break;

        case UIState.CREDS:
            set_over_boxes (app.current_item.actor, true);
            break;

        case UIState.DISPLAY: {
            float x, y;
            var display = app.current_item.actor;

            actor.hide ();
            actor_remove (app.properties.actor);

            if (previous_ui_state == UIState.CREDS) {
                /* move display/machine actor to stage, keep same position */
                display.get_transformed_position (out x, out y);
                actor_remove (display);
                actor_add (display, app.stage);
                display.set_position (x, y);
            }
            break;
        }

        case UIState.WIZARD:
            app.wizard.actor.add_constraint (new Clutter.BindConstraint (over_boxes, BindCoordinate.SIZE, 0));
            set_over_boxes (app.wizard.actor);
            break;

        case UIState.PROPERTIES:
            actor_remove (app.current_item.actor);
            app.properties.actor.add_constraint (new Clutter.BindConstraint (over_boxes, BindCoordinate.SIZE, 0));
            set_over_boxes (app.properties.actor);
            break;

        default:
            break;
        }

        if (app.current_item != null)
            app.current_item.ui_state = ui_state;
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

        var iter = append (machine.pixbuf, machine.name, item);
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

        return_if_fail (iter != null);

        model.remove (iter);
        item.set_data<Gtk.TreeIter?> ("iter", null);
        item.disconnect (pixbuf_id);
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

            return strcmp (item_a.name.down (), item_b.name.down ());
        });
        model.set_sort_column_id (Gtk.SortColumn.DEFAULT, Gtk.SortType.ASCENDING);

        icon_view = new Gtk.IconView.with_model (model);
        icon_view.item_width = 185;
        icon_view.column_spacing = 20;
        icon_view.margin = 16;
        icon_view_activate_on_single_click (icon_view, true);
        icon_view.set_selection_mode (Gtk.SelectionMode.SINGLE);
        icon_view.item_activated.connect ((view, path) => {
            var item = get_item_for_path (path);
            app.item_selected (item);
        });
        icon_view.selection_changed.connect (() => {
            app.notify_property ("selected-items");
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

        over_boxes = new Clutter.Box (new Clutter.BinLayout (Clutter.BinAlignment.FILL, Clutter.BinAlignment.FILL));
        over_boxes.add_constraint_with_name ("top-box-size",
                                             new Clutter.BindConstraint (gtkactor, BindCoordinate.SIZE, 0));
        over_boxes.add_constraint_with_name ("top-box-position",
                                             new Clutter.BindConstraint (gtkactor, BindCoordinate.POSITION, 0));

        app.state.set_key (null, "creds", actor, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 0, 0, 0);
        app.state.set_key (null, "display", actor, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 0, 0, 0);
        app.state.set_key (null, "collection", actor, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 255, 0, 0);
        app.state.set_key (null, "display", over_boxes, "x", AnimationMode.EASE_OUT_QUAD, (float) 0, 0, 0);
        app.state.set_key (null, "display", over_boxes, "y", AnimationMode.EASE_OUT_QUAD, (float) 0, 0, 0);
    }
}
