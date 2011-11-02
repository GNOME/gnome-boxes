// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;

private class Boxes.CollectionView: Boxes.UI {
    public override Clutter.Actor actor { get { return margin; } }

    private App app;
    private Clutter.Group margin; // the surrounding actor, for the margin
    private Clutter.Box boxes; // the boxes list box
    private SortedCollection sorted;
    private Clutter.FlowLayout layout;
    private Clutter.Box over_boxes; // a box on top of boxes list

    private Category _category;
    public Category category {
        get { return _category; }
        set {
            _category = value;
            if (sorted != null)
                update_view ();
        }
    }

    public CollectionView (App app, Category category) {
        this.app = app;
        this.category = category;
        sorted = new SortedCollection ((a, b) => {
            return strcmp (a.name.down (), b.name.down ());
        });
        setup_view ();
    }

    private void set_main_ui_state () {
        actor_remove (app.wizard.actor);
        actor_remove (app.properties.actor);
        if (app.current_item != null)
            actor_remove (app.current_item.actor);

        /* follow main table layout again */
        actor_unpin (boxes);
        boxes.set_position (15f, 15f);
        margin.add_constraint_with_name ("boxes-left",
                                         new Clutter.SnapConstraint (app.stage, SnapEdge.RIGHT, SnapEdge.RIGHT, 0));
        margin.add_constraint_with_name ("boxes-bottom",
                                         new Clutter.SnapConstraint (app.stage, SnapEdge.BOTTOM, SnapEdge.RIGHT.BOTTOM, 0));
        /* normal flow items */
        boxes.set_layout_manager (layout);

        actor_remove (over_boxes);
    }

    public void set_over_boxes () {
        remove_item (app.current_item);
        over_boxes.pack (app.current_item.actor,
                         "x-align", Clutter.BinAlignment.CENTER,
                         "y-align", Clutter.BinAlignment.CENTER);
        actor_add (over_boxes, app.stage);
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.CREDS:
            set_over_boxes ();
            app.current_item.ui_state = UIState.CREDS;

            /* item don't move anymore */
            boxes.set_layout_manager (new Clutter.FixedLayout ());

            break;

        case UIState.DISPLAY: {
            float x, y;
            var display = app.current_item.actor;

            if (previous_ui_state == UIState.CREDS) {
                /* move display/machine actor to stage, keep same position */
                display.get_transformed_position (out x, out y);
                actor_remove (display);
                actor_add (display, app.stage);
                display.set_position (x, y);

                /* make sure the boxes stay where they are */
                boxes.get_transformed_position (out x, out y);
                boxes.set_position (x, y);
                actor_pin (boxes);
                margin.remove_constraint_by_name ("boxes-left");
                margin.remove_constraint_by_name ("boxes-bottom");
            }

            app.current_item.ui_state = UIState.DISPLAY;

            break;
        }

        case UIState.COLLECTION:
            set_main_ui_state ();
            if (app.current_item != null)
                add_item (app.current_item);
            break;

        case UIState.WIZARD:
        case UIState.PROPERTIES:
            set_main_ui_state ();
            over_boxes.pack (ui_state == UIState.WIZARD ? app.wizard.actor : app.properties.actor);
            app.wizard.actor.add_constraint (new Clutter.BindConstraint (over_boxes, BindCoordinate.SIZE, 0));
            actor_add (over_boxes, app.stage);
            if (app.current_item != null)
                app.current_item.ui_state = ui_state;
            break;

        default:
            break;
        }
    }

    public void update_item_visible (CollectionItem item) {
        var visible = false;

        if (item is Machine) {
            var machine = item as Machine;

            switch (category.kind) {
            case Category.Kind.USER:
                visible = category.name in machine.source.categories;
                break;
            case Category.Kind.NEW:
                visible = true;
                break;
            }
        }

        item.actor.visible = visible;
    }

    public void update_view () {
        var iter = sorted.sequence.get_begin_iter ();

        while (!iter.is_end ()) {
            var item = iter.get ();
            update_item_visible (item);
            iter = iter.next ();
        }
    }

    public void add_item (CollectionItem item) {
        var machine = item as Machine;

        if (machine == null) {
            warning ("Cannot add item %p in %s".printf (&item, sorted.to_string ()));
            return;
        }

        item.ui_state = UIState.COLLECTION;
        actor_remove (item.actor);

        var iter = sorted.insert (item);

        if (iter.is_begin ())
            boxes.pack_before (item.actor, null);
        else {
            var prev = iter.prev ().get ();
            boxes.pack_after (item.actor, prev.actor);
        }

        update_item_visible (item);
    }

    public void remove_item (CollectionItem item) {
        if (item is Machine) {
            var machine = item as Machine;
            var actor = machine.actor;

            sorted.remove (machine);
            if (actor.get_parent () == boxes)
                boxes.remove_actor (actor);
        } else
            warning ("Cannot remove item %p".printf (&item));
    }

    private void setup_view () {
        layout = new Clutter.FlowLayout (Clutter.FlowOrientation.HORIZONTAL);
        margin = new Clutter.Group ();
        margin.set_clip_to_allocation (true);
        margin.set_reactive (true);
        /* this helps to keep the app table inside the window, otherwise, it allocated large */
        margin.set_size (1f, 1f);

        boxes = new Clutter.Box (layout);
        layout.set_column_spacing (35);
        layout.set_row_spacing (25);
        margin.add (boxes);
        app.box.pack (margin, "column", 1, "row", 1, "x-expand", true, "y-expand", true);

        margin.scroll_event.connect ((event) => {
            float scrollable_height = boxes.get_height ();

            boxes.get_preferred_height (boxes.get_width (), null, out scrollable_height);
            var viewport_height = margin.get_height ();

            if (scrollable_height < viewport_height)
                return true;
            var y = boxes.get_y ();
            switch (event.direction) {
            case ScrollDirection.UP:
                y += 50f;
                break;
            case ScrollDirection.DOWN:
                y -= 50f;
                break;
            default:
                break;
            }
            y = y.clamp (viewport_height - scrollable_height, 0.0f);
            boxes.animate (AnimationMode.LINEAR, 50, "y", y);
            return true;
        });

        boxes.add_constraint_with_name ("boxes-width",
                                        new Clutter.BindConstraint (margin, BindCoordinate.WIDTH, -25f));

        over_boxes = new Clutter.Box (new Clutter.BinLayout (Clutter.BinAlignment.FILL, Clutter.BinAlignment.FILL));
        over_boxes.add_constraint_with_name ("top-box-size",
                                             new Clutter.BindConstraint (margin, BindCoordinate.SIZE, 0));
        over_boxes.add_constraint_with_name ("top-box-position",
                                             new Clutter.BindConstraint (margin, BindCoordinate.POSITION, 0));

        app.state.set_key (null, "creds", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 0, 0, 0);
        app.state.set_key (null, "display", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 0, 0, 0);
        app.state.set_key (null, "collection", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 255, 0, 0);
        app.state.set_key (null, "display", over_boxes, "x", AnimationMode.EASE_OUT_QUAD, (float) 0, 0, 0);
        app.state.set_key (null, "display", over_boxes, "y", AnimationMode.EASE_OUT_QUAD, (float) 0, 0, 0);
    }

    private class SortedCollection: GLib.Object {
        public GLib.Sequence<CollectionItem> sequence = new GLib.Sequence<CollectionItem> ();
        CompareDataFunc<CollectionItem> compare;

        public SortedCollection(owned CompareDataFunc<CollectionItem> compare) {
            this.compare = (owned) compare;
        }

        public SequenceIter<CollectionItem> insert (owned CollectionItem item) {
            return sequence.insert_sorted (item, compare);
        }

        public void remove (CollectionItem item) {
            var iter = sequence.lookup (item, compare);
            if (iter != null)
                sequence.remove (iter);
        }

        public string to_string () {
            var str = "";

            var iter = sequence.get_begin_iter ();
            while (!iter.is_end ()) {
                str += iter.get ().name + " ";
                iter = iter.next ();
            }

            return str;
        }
    }
}
