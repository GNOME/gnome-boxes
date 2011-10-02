using GLib;
using Clutter;

class Boxes.CollectionView: Boxes.UI {
    App app;

    Clutter.Group actor; // the surrounding actor, for the margin
    Clutter.Box boxes; // the boxes list box
    Clutter.FlowLayout flow;
    Clutter.Box actor_onebox; // a box on top of boxes list

    public CollectionView (App app) {
        this.app = app;
        setup_view ();
    }

    private void setup_view () {
        flow = new Clutter.FlowLayout (Clutter.FlowOrientation.HORIZONTAL);
        actor = new Clutter.Group ();
        boxes = new Clutter.Box (flow);
        flow.set_column_spacing (35);
        flow.set_row_spacing (25);
        actor.add (boxes);
        app.cbox.pack (actor, "column", 1, "row", 1, "x-expand", true, "y-expand", true);

        boxes.set_position (15f, 15f);
        boxes.add_constraint_with_name ("boxes-width", new Clutter.BindConstraint (actor, BindCoordinate.WIDTH, -25f));
        boxes.add_constraint_with_name ("boxes-height", new Clutter.BindConstraint (actor, BindCoordinate.HEIGHT, -25f));
     // FIXME! report bug to clutter about flow inside table
        actor.add_constraint_with_name ("boxes-left", new Clutter.SnapConstraint (app.cstage, SnapEdge.RIGHT, SnapEdge.RIGHT, 0));
        actor.add_constraint_with_name ("boxes-bottom", new Clutter.SnapConstraint (app.cstage, SnapEdge.BOTTOM, SnapEdge.RIGHT.BOTTOM, 0));

        actor_onebox = new Clutter.Box (new Clutter.BinLayout (Clutter.BinAlignment.FILL, Clutter.BinAlignment.FILL));
        actor_onebox.add_constraint_with_name ("onebox-size", new Clutter.BindConstraint (actor, BindCoordinate.SIZE, 0));
        actor_onebox.add_constraint_with_name ("onebox-position", new Clutter.BindConstraint (actor, BindCoordinate.POSITION, 0));
        app.cstage.add_actor (actor_onebox);

        app.cstate.set_key (null, "creds", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint)0, 0, 0);
        app.cstate.set_key (null, "display", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint)0, 0, 0);
        app.cstate.set_key (null, "collection", boxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint)255, 0, 0);
        app.cstate.set_key (null, "display", actor_onebox, "x", AnimationMode.EASE_OUT_QUAD, (float)0, 0, 0);
        app.cstate.set_key (null, "display", actor_onebox, "y", AnimationMode.EASE_OUT_QUAD, (float)0, 0, 0);
    }

    public void add_item (CollectionItem item) {
        if (item is Box) {
            var box = (Box)item;

            box.actor.ui_state = UIState.COLLECTION;
            actor_add (box.get_clutter_actor (), boxes);
        } else {
            warning ("Cannot add item %p".printf (&item));
        }
    }

    public void remove_item (CollectionItem item) {
        if (item is Box) {
            var box = (Box)item;
            var actor = box.get_clutter_actor ();
            if (actor.get_parent () == this.boxes)
                this.boxes.remove_actor (actor); // FIXME: why Clutter warn here??!
        } else {
            warning ("Cannot remove item %p".printf (&item));
        }
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.CREDS: {
            remove_item (app.box);
            app.box.actor.ui_state = UIState.CREDS;

            actor_onebox.pack (app.box.get_clutter_actor (),
                               "x-align", Clutter.BinAlignment.CENTER,
                               "y-align", Clutter.BinAlignment.CENTER);

            this.boxes.set_layout_manager (new Clutter.FixedLayout ());
            break;
        }
        case UIState.DISPLAY: {
            float x, y;
            var a = app.box.get_clutter_actor ();

            /* move box actor to stage */
            a.get_transformed_position (out x, out y);
            if (a.get_parent () == actor_onebox)
                actor_onebox.remove_actor (a);
            if (a.get_parent () != app.cstage)
                app.cstage.add_actor (a);
            a.set_position (x, y);

            app.box.actor.ui_state = UIState.DISPLAY;
            break;
        }
        case UIState.COLLECTION: {
            boxes.set_layout_manager (flow);

            if (app.box == null)
                break;

            var a = app.box.get_clutter_actor ();
            if (a.get_parent () == actor_onebox)
                actor_onebox.remove_actor (a);
            add_item (app.box);

            break;
        }
        default:
            break;
        }
    }
}
