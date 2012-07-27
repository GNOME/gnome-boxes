// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;

public class Boxes.Revealer: Clutter.Actor {
    private bool horizontal;
    private bool children_visible;
    public uint duration;
    public bool resize;

    private bool _revealed;
    public bool revealed {
        get {
            return _revealed;
        }
        set {
            if (_revealed == value)
                return;

            _revealed = value;
            if (value)
                reveal ();
            else
                unreveal ();
        }
    }


    public Revealer (bool horizontal) {
        this.horizontal = horizontal;
        clip_to_allocation = true;
        children_visible = true;
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
            if (children_visible)
                child.show ();
            else
                child.hide ();
        });
    }

    public void reveal () {
        if (resize) {
            if (horizontal)
                height = 0.0f;
            else
                width = 0.0f;
        }

        var max = 0.0f;
        foreach (var child in get_children ()) {
            if (!children_visible)
                child.show ();
            if (horizontal) {
                if (!children_visible) {
                    float height;
                    child.get_preferred_height (-1, null, out height);
                    child.y = -height;
                    max = float.max (max, height);
                }
                child.animate (Clutter.AnimationMode.EASE_IN_QUAD, duration, "y", 0f);
            } else {
                if (!children_visible) {
                    float width;
                    child.get_preferred_width (-1, null, out width);
                    child.x = -width;
                    max = float.max (max, width);
                }
                child.animate (Clutter.AnimationMode.EASE_IN_QUAD, duration, "x", 0f);
            }
        }

        if (resize) {
            if (horizontal)
                animate (Clutter.AnimationMode.EASE_IN_QUAD, duration, "height", max);
            else
                animate (Clutter.AnimationMode.EASE_IN_QUAD, duration, "width", max);
        }

        children_visible = true;
    }

    private void unreveal_child (Clutter.Actor child) {
        if (horizontal) {
            float height;
            child.get_preferred_height (-1, null, out height);
            var anim = child.animate (Clutter.AnimationMode.EASE_OUT_QUAD, duration, "y", -height);
            anim.completed.connect (() => {
                child.hide ();
                children_visible = false;
            });
        } else {
            float width;
            child.get_preferred_width (-1, null, out width);
            var anim = child.animate (Clutter.AnimationMode.EASE_OUT_QUAD, duration, "x", -width);
            anim.completed.connect (() => {
                child.hide ();
                children_visible = false;
            });
        }

        if (resize) {
            if (horizontal)
                animate (Clutter.AnimationMode.EASE_OUT_QUAD, duration, "height", 0.0f);
            else
                animate (Clutter.AnimationMode.EASE_OUT_QUAD, duration, "width", 0.0f);
        }
    }

    public void unreveal () {
        if (!children_visible)
            return;

        bool found_child = false;
        foreach (var child in get_children ()) {
            found_child = true;
            unreveal_child (child);
        }
        if (!found_child)
            children_visible = false;
    }
}
