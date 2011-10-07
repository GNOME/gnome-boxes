// This file is part of GNOME Boxes. License: LGPLv2
using Clutter;

private class Boxes.CollectionView: Boxes.UI {
    public override Clutter.Actor actor { get { return margin; } }

    private App app;
    private Clutter.Group margin; // the surrounding actor, for the margin
    private Clutter.Box boxes; // the boxes list box
    private Clutter.FlowLayout layout;
    private Clutter.Box over_boxes; // a box on top of boxes list

    public CollectionView (App app) {
        this.app = app;
        setup_view ();
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.CREDS:
            over_boxes.add_constraint_with_name ("top-box-size",
                                                 new Clutter.BindConstraint (margin, BindCoordinate.SIZE, 0));
            over_boxes.add_constraint_with_name ("top-box-position",
                                                 new Clutter.BindConstraint (margin, BindCoordinate.POSITION, 0));
            actor_add (over_boxes, app.stage);

            remove_item (app.current_item);
            app.current_item.ui_state = UIState.CREDS;

            over_boxes.pack (app.current_item.actor,
                             "x-align", Clutter.BinAlignment.CENTER,
                             "y-align", Clutter.BinAlignment.CENTER);

            boxes.set_layout_manager (new Clutter.FixedLayout ());

            break;

        case UIState.DISPLAY: {
            float x, y;
            var actor = app.current_item.actor;

            /* move box actor to stage */
            actor.get_transformed_position (out x, out y);
            if (actor.get_parent () == over_boxes)
                over_boxes.remove_actor (actor);
            if (actor.get_parent () != app.stage)
                app.stage.add_actor (actor);
            actor.set_position (x, y);

            app.current_item.ui_state = UIState.DISPLAY;

            break;
        }

        case UIState.COLLECTION:
            boxes.set_layout_manager (layout);

            if (app.current_item == null)
                break;

            var actor = app.current_item.actor;
            if (actor.get_parent () == over_boxes)
                over_boxes.remove_actor (actor);
            add_item (app.current_item);

            break;

        default:
            break;
        }
    }

    public void add_item (CollectionItem item) {
        if (item is Machine) {
            var machine = item as Machine;

            machine.machine_actor.ui_state = UIState.COLLECTION;
            actor_add (machine.actor, boxes);
        } else
            warning ("Cannot add item %p".printf (&item));
    }

    public void remove_item (CollectionItem item) {
        if (item is Machine) {
            var machine = item as Machine;
            var actor = machine.actor;
            if (actor.get_parent () == boxes)
                boxes.remove_actor (actor); // FIXME: why Clutter warn here??!
        } else
            warning ("Cannot remove item %p".printf (&item));
    }

    private void setup_view () {
        layout = new Clutter.FlowLayout (Clutter.FlowOrientation.HORIZONTAL);
        margin = new Clutter.Group ();
        boxes = new Clutter.Box (layout);
        layout.set_column_spacing (35);
        layout.set_row_spacing (25);
        margin.add (boxes);
        app.box.pack (margin, "column", 1, "row", 1, "x-expand", true, "y-expand", true);

        boxes.set_position (15f, 15f);
        boxes.add_constraint_with_name ("boxes-width",
                                        new Clutter.BindConstraint (margin, BindCoordinate.WIDTH, -25f));
        boxes.add_constraint_with_name ("boxes-height",
                                        new Clutter.BindConstraint (margin, BindCoordinate.HEIGHT, -25f));
        // FIXME! report bug to clutter about flow inside table
        margin.add_constraint_with_name ("boxes-left",
                                         new Clutter.SnapConstraint (app.stage, SnapEdge.RIGHT, SnapEdge.RIGHT, 0));
        margin.add_constraint_with_name ("boxes-bottom",
                                         new Clutter.SnapConstraint (app.stage, SnapEdge.BOTTOM, SnapEdge.RIGHT.BOTTOM, 0));

        over_boxes = new Clutter.Box (new Clutter.BinLayout (Clutter.BinAlignment.FILL, Clutter.BinAlignment.FILL));

        app.state.set_key (null, "creds", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 0, 0, 0);
        app.state.set_key (null, "display", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 0, 0, 0);
        app.state.set_key (null, "collection", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 255, 0, 0);
        app.state.set_key (null, "display", over_boxes, "x", AnimationMode.EASE_OUT_QUAD, (float) 0, 0, 0);
        app.state.set_key (null, "display", over_boxes, "y", AnimationMode.EASE_OUT_QUAD, (float) 0, 0, 0);
    }
}
