using GLib;
using Clutter;

class CollectionView: BoxesUI {
    Boxes boxes;

    Clutter.Box actor; // the boxes list box
    Clutter.FlowLayout actor_flow;
    Clutter.Box actor_onebox; // a box on top of boxes list

    public CollectionView (Boxes boxes) {
        this.boxes = boxes;
        setup_view ();
    }

    private void setup_view () {
        actor_flow = new Clutter.FlowLayout (Clutter.FlowOrientation.HORIZONTAL);
        actor = new Clutter.Box (actor_flow);
        actor_flow.set_column_spacing (35);
        actor_flow.set_row_spacing (25);

        // for (var i = 0; i < 7; ++i) {
        //     var box = new Box ("vm %d".printf(i));
        //  add_box (box);
        // }
        boxes.cbox.pack (actor, "column", 1, "row", 1, "x-expand", true, "y-expand", true);

        // FIXME! report bug to clutter about flow inside table
        actor.add_constraint_with_name ("boxes-left", new Clutter.SnapConstraint (boxes.cstage, SnapEdge.RIGHT, SnapEdge.RIGHT, 0));
        actor.add_constraint_with_name ("boxes-bottom", new Clutter.SnapConstraint (boxes.cstage, SnapEdge.BOTTOM, SnapEdge.RIGHT.BOTTOM, 0));

        actor_onebox = new Clutter.Box (new Clutter.BinLayout (Clutter.BinAlignment.FILL, Clutter.BinAlignment.FILL));
        actor_onebox.add_constraint_with_name ("onebox-size", new Clutter.BindConstraint (actor, BindCoordinate.SIZE, 0));
        actor_onebox.add_constraint_with_name ("onebox-position", new Clutter.BindConstraint (actor, BindCoordinate.POSITION, 0));
        boxes.cstage.add_actor (actor_onebox);

        boxes.cstate.set_key (null, "creds", actor, "opacity", AnimationMode.EASE_OUT_QUAD, (uint)0, 0, 0);
        boxes.cstate.set_key (null, "remote", actor, "opacity", AnimationMode.EASE_OUT_QUAD, (uint)0, 0, 0);
        boxes.cstate.set_key (null, "collection", actor, "opacity", AnimationMode.EASE_OUT_QUAD, (uint)255, 0, 0);
        boxes.cstate.set_key (null, "remote", actor_onebox, "x", AnimationMode.EASE_OUT_QUAD, (float)0, 0, 0);
        boxes.cstate.set_key (null, "remote", actor_onebox, "y", AnimationMode.EASE_OUT_QUAD, (float)0, 0, 0);
    }

    public void add_item (CollectionItem item) {
        if (item is Box) {
            var box = (Box)item;
            var actor = box.actor;
            var cactor = box.get_clutter_actor ();
            actor.scale_texture ();
            actor.entry.set_can_focus (false);
            actor.entry.hide ();
            actor.label.show ();
            this.actor.add_actor (cactor);
        } else {
            warning ("Cannot add item %p".printf (&item));
        }
    }

    public void remove_item (CollectionItem item) {
        if (item is Box) {
            var box = (Box)item;
            var actor = box.get_clutter_actor ();
            this.actor.remove_actor (actor);
        } else {
            warning ("Cannot remove item %p".printf (&item));
        }
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.CREDS: {
            var actor = boxes.box.actor;
            var cactor = actor.actor;

            remove_item (boxes.box);

            actor.scale_texture (2.0f);
            actor.entry.show ();
            //      actor.entry.set_sensitive (false); FIXME: depending on spice-gtk conn. results
            actor.entry.set_can_focus (true);
            actor.entry.grab_focus ();

            actor_onebox.pack (cactor,
                               "x-align", Clutter.BinAlignment.CENTER,
                               "y-align", Clutter.BinAlignment.CENTER);

            this.actor.set_layout_manager (new Clutter.FixedLayout ());
            break;
        }
        case UIState.REMOTE: {
            var actor = boxes.box.actor;
            var cactor = actor.actor;
            float x, y;

            actor.entry.hide ();
            actor.label.hide ();

            cactor.get_transformed_position (out x, out y);
            actor_onebox.remove_actor (cactor);
            boxes.cstage.add_actor (cactor);
            cactor.set_position (x, y);

            int w, h;
            boxes.window.get_size (out w, out h);
            actor.ctexture.animate (Clutter.AnimationMode.LINEAR, 555,
                                    "width", (float)w,
                                    "height", (float)h);
            actor.actor.animate (Clutter.AnimationMode.LINEAR, 555,
                                 "x", 0.0f,
                                 "y", 0.0f);


            break;
        }
        case UIState.COLLECTION: {
            if (boxes.box == null)
                break;

            var actor = boxes.box.actor;
            var cactor = actor.actor;

            actor_onebox.remove_actor (cactor);
            add_item (boxes.box);

            this.actor.set_layout_manager (actor_flow);
            break;
        }
        default:
            break;
        }
    }
}
