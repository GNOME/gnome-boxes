// This file is part of GNOME Boxes. License: LGPLv2
using Clutter;

private class Boxes.CollectionView: Boxes.UI {
    private App app;

    private Clutter.Group actor; // the surrounding actor, for the margin
    private Clutter.Box boxes; // the boxes list box
    private Clutter.FlowLayout layout;
    private Clutter.Box top_box; // a box on top of boxes list

    public CollectionView (App app) {
        this.app = app;
        setup_view ();
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.CREDS:
            remove_item (app.selected_box);
            app.selected_box.actor.ui_state = UIState.CREDS;

            top_box.pack (app.selected_box.get_clutter_actor (),
                          "x-align", Clutter.BinAlignment.CENTER,
                          "y-align", Clutter.BinAlignment.CENTER);

            boxes.set_layout_manager (new Clutter.FixedLayout ());

            break;

        case UIState.DISPLAY: {
            float x, y;
            var actor = app.selected_box.get_clutter_actor ();

            /* move box actor to stage */
            actor.get_transformed_position (out x, out y);
            if (actor.get_parent () == top_box)
                top_box.remove_actor (actor);
            if (actor.get_parent () != app.stage)
                app.stage.add_actor (actor);
            actor.set_position (x, y);

            app.selected_box.actor.ui_state = UIState.DISPLAY;

            break;
        }

        case UIState.COLLECTION:
            boxes.set_layout_manager (layout);

            if (app.selected_box == null)
                break;

            var actor = app.selected_box.get_clutter_actor ();
            if (actor.get_parent () == top_box)
                top_box.remove_actor (actor);
            add_item (app.selected_box);

            break;

        default:
            break;
        }
    }

    public void add_item (CollectionItem item) {
        if (item is Box) {
            var box = (Box)item;

            box.actor.ui_state = UIState.COLLECTION;
            actor_add (box.get_clutter_actor (), boxes);
        } else
            warning ("Cannot add item %p".printf (&item));
    }

    public void remove_item (CollectionItem item) {
        if (item is Box) {
            var box = (Box)item;
            var actor = box.get_clutter_actor ();
            if (actor.get_parent () == boxes)
                boxes.remove_actor (actor); // FIXME: why Clutter warn here??!
        } else
            warning ("Cannot remove item %p".printf (&item));
    }

    private void setup_view () {
        layout = new Clutter.FlowLayout (Clutter.FlowOrientation.HORIZONTAL);
        actor = new Clutter.Group ();
        boxes = new Clutter.Box (layout);
        layout.set_column_spacing (35);
        layout.set_row_spacing (25);
        actor.add (boxes);
        app.box.pack (actor, "column", 1, "row", 1, "x-expand", true, "y-expand", true);

        boxes.set_position (15f, 15f);
        boxes.add_constraint_with_name ("boxes-width",
                                        new Clutter.BindConstraint (actor, BindCoordinate.WIDTH, -25f));
        boxes.add_constraint_with_name ("boxes-height",
                                        new Clutter.BindConstraint (actor, BindCoordinate.HEIGHT, -25f));
        // FIXME! report bug to clutter about flow inside table
        actor.add_constraint_with_name ("boxes-left",
                                        new Clutter.SnapConstraint (app.stage, SnapEdge.RIGHT, SnapEdge.RIGHT, 0));
        actor.add_constraint_with_name ("boxes-bottom",
                                        new Clutter.SnapConstraint (app.stage, SnapEdge.BOTTOM, SnapEdge.RIGHT.BOTTOM, 0));

        top_box = new Clutter.Box (new Clutter.BinLayout (Clutter.BinAlignment.FILL, Clutter.BinAlignment.FILL));
        top_box.add_constraint_with_name ("top-box-size",
                                          new Clutter.BindConstraint (actor, BindCoordinate.SIZE, 0));
        top_box.add_constraint_with_name ("top-box-position",
                                          new Clutter.BindConstraint (actor, BindCoordinate.POSITION, 0));
        app.stage.add_actor (top_box);

        app.state.set_key (null, "creds", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 0, 0, 0);
        app.state.set_key (null, "display", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 0, 0, 0);
        app.state.set_key (null, "collection", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 255, 0, 0);
        app.state.set_key (null, "display", top_box, "x", AnimationMode.EASE_OUT_QUAD, (float) 0, 0, 0);
        app.state.set_key (null, "display", top_box, "y", AnimationMode.EASE_OUT_QUAD, (float) 0, 0, 0);
    }
}
