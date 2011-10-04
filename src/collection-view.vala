using GLib;
using Clutter;

class Boxes.CollectionView: Boxes.UI {
    private App app;

    private Clutter.Group actor; // the surrounding actor, for the margin
    private Clutter.Box boxes; // the boxes list box
    private Clutter.FlowLayout layout;
    private Clutter.Box top_box; // a box on top of boxes list

    public CollectionView (App app) {
        this.app = app;
        this.setup_view ();
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.CREDS:
            this.remove_item (this.app.selected_box);
            this.app.selected_box.actor.ui_state = UIState.CREDS;

            this.top_box.pack (this.app.selected_box.get_clutter_actor (),
                               "x-align", Clutter.BinAlignment.CENTER,
                               "y-align", Clutter.BinAlignment.CENTER);

            this.boxes.set_layout_manager (new Clutter.FixedLayout ());

            break;

        case UIState.DISPLAY: {
            float x, y;
            var actor = this.app.selected_box.get_clutter_actor ();

            /* move box actor to stage */
            actor.get_transformed_position (out x, out y);
            if (actor.get_parent () == this.top_box)
                this.top_box.remove_actor (actor);
            if (actor.get_parent () != this.app.stage)
                this.app.stage.add_actor (actor);
            actor.set_position (x, y);

            this.app.selected_box.actor.ui_state = UIState.DISPLAY;

            break;
        }

        case UIState.COLLECTION:
            this.boxes.set_layout_manager (this.layout);

            if (this.app.selected_box == null)
                break;

            var actor = this.app.selected_box.get_clutter_actor ();
            if (actor.get_parent () == this.top_box)
                this.top_box.remove_actor (actor);
            this.add_item (this.app.selected_box);

            break;

        default:

            break;
        }
    }

    public void add_item (CollectionItem item) {
        if (item is Box) {
            var box = (Box)item;

            box.actor.ui_state = UIState.COLLECTION;
            actor_add (box.get_clutter_actor (), this.boxes);
        } else
            warning ("Cannot add item %p".printf (&item));
    }

    public void remove_item (CollectionItem item) {
        if (item is Box) {
            var box = (Box)item;
            var actor = box.get_clutter_actor ();
            if (actor.get_parent () == this.boxes)
                this.boxes.remove_actor (actor); // FIXME: why Clutter warn here??!
        } else
            warning ("Cannot remove item %p".printf (&item));
    }

    private void setup_view () {
        this.layout = new Clutter.FlowLayout (Clutter.FlowOrientation.HORIZONTAL);
        this.actor = new Clutter.Group ();
        this.boxes = new Clutter.Box (this.layout);
        this.layout.set_column_spacing (35);
        this.layout.set_row_spacing (25);
        this.actor.add (this.boxes);
        this.app.box.pack (this.actor, "column", 1, "row", 1, "x-expand", true, "y-expand", true);

        this.boxes.set_position (15f, 15f);
        this.boxes.add_constraint_with_name ("boxes-width",
                                             new Clutter.BindConstraint (this.actor, BindCoordinate.WIDTH, -25f));
        this.boxes.add_constraint_with_name ("boxes-height",
                                             new Clutter.BindConstraint (this.actor, BindCoordinate.HEIGHT, -25f));
        // FIXME! report bug to clutter about flow inside table
        this.actor.add_constraint_with_name ("boxes-left", new Clutter.SnapConstraint (this.app.stage,
                                                                                       SnapEdge.RIGHT,
                                                                                       SnapEdge.RIGHT,
                                                                                       0));
        this.actor.add_constraint_with_name ("boxes-bottom", new Clutter.SnapConstraint (this.app.stage,
                                                                                         SnapEdge.BOTTOM,
                                                                                         SnapEdge.RIGHT.BOTTOM,
                                                                                         0));

        this.top_box = new Clutter.Box (new Clutter.BinLayout (Clutter.BinAlignment.FILL, Clutter.BinAlignment.FILL));
        this.top_box.add_constraint_with_name ("top-box-size",
                                         new Clutter.BindConstraint (this.actor, BindCoordinate.SIZE, 0));
        this.top_box.add_constraint_with_name ("top-box-position",
                                         new Clutter.BindConstraint (this.actor, BindCoordinate.POSITION, 0));
        this.app.stage.add_actor (this.top_box);

        this.app.state.set_key (null, "creds", this.boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 0, 0, 0);
        this.app.state.set_key (null, "display", this.boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint) 0, 0, 0);
        this.app.state.set_key (null,
                                "collection",
                                this.boxes,
                                "opacity",
                                AnimationMode.EASE_OUT_QUAD,
                                (uint) 255,
                                0,
                                0);
        this.app.state.set_key (null, "display", this.top_box, "x", AnimationMode.EASE_OUT_QUAD, (float) 0, 0, 0);
        this.app.state.set_key (null, "display", this.top_box, "y", AnimationMode.EASE_OUT_QUAD, (float) 0, 0, 0);
    }
}
