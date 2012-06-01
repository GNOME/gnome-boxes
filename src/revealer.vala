// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;

public class Boxes.Revealer: Clutter.Actor {
    private bool horizontal;
    private bool revealed;
    public uint duration;

    public Revealer (bool horizontal) {
        this.horizontal = horizontal;
        clip_to_allocation = true;
        revealed = true;
        duration = 250;

        if (horizontal) {
            var layout = new Clutter.BinLayout (Clutter.BinAlignment.FILL,
                                                Clutter.BinAlignment.FIXED);
            this.set_layout_manager (layout);
        } else {
            var layout = new Clutter.BinLayout (Clutter.BinAlignment.FIXED,
                                                Clutter.BinAlignment.FILL);
            this.set_layout_manager (layout);
        }

        this.actor_added.connect ( (child) => {
            if (revealed)
                child.show ();
            else
                child.hide ();
        });
    }

    public void reveal () {
        foreach (var child in get_children ()) {
            if (!revealed)
                child.show ();
            if (horizontal) {
                if (!revealed) {
                    float height;
                    child.get_preferred_height (-1, null, out height);
                    child.y = -height;
                }
                child.animate (Clutter.AnimationMode.EASE_IN_QUAD, duration, "y", 0f);
            } else {
                if (!revealed) {
                    float width;
                    child.get_preferred_width (-1, null, out width);
                    child.x = -width;
                }
                child.animate (Clutter.AnimationMode.EASE_IN_QUAD, duration, "x", 0f);
            }
        }
        revealed = true;
    }

    private void unreveal_child (Clutter.Actor child) {
        if (horizontal) {
            float height;
            child.get_preferred_height (-1, null, out height);
            var anim = child.animate (Clutter.AnimationMode.EASE_OUT_QUAD, duration, "y", -height);
            anim.completed.connect (() => {
                child.hide ();
                revealed = false;
            });
        } else {
            float width;
            child.get_preferred_width (-1, null, out width);
            var anim = child.animate (Clutter.AnimationMode.EASE_OUT_QUAD, duration, "x", -width);
            anim.completed.connect (() => {
                child.hide ();
                revealed = false;
            });
        }
    }

    public void unreveal () {
        if (!revealed)
            return;

        bool found_child = false;
        foreach (var child in get_children ()) {
            found_child = true;
            unreveal_child (child);
        }
        if (!found_child)
            revealed = false;
    }
}
