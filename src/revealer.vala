// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;

public class Boxes.RevealerLayout : Clutter.FixedLayout {
    private bool horizontal;

    public RevealerLayout (bool horizontal) {
        this.horizontal = horizontal;
    }

    public override void allocate (Clutter.Container container, Clutter.ActorBox allocation, Clutter.AllocationFlags flags) {
        foreach (var child in (container as Clutter.Actor).get_children ()) {
            float width, height;
            float availible_w, availible_h;

            child.get_preferred_size (null, null, out width, out height);
            allocation.get_size (out availible_w, out availible_h);

            Clutter.ActorBox box = { 0, 0, width, height };

            if (horizontal)
                box.x2 = availible_w;
            else
                box.y2 = availible_h;

            child.allocate (box, flags);
        }
    }
}

public class Boxes.Revealer: Clutter.Actor {
    private bool horizontal;
    private bool children_visible;
    private string animation_prop;
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
        if (horizontal)
            animation_prop = "translation-y";
        else
            animation_prop = "translation-x";
        clip_to_allocation = true;
        children_visible = true;
        duration = 250;

        this.set_layout_manager (new RevealerLayout(horizontal));
        if (horizontal)
            this.x_expand = true;
        else
            this.y_expand = true;

        this.actor_added.connect ( (child) => {
            if (horizontal)
                child.x_align = Clutter.ActorAlign.FILL;
            else
                child.y_align = Clutter.ActorAlign.FILL;

            if (children_visible)
                child.show ();
            else
                child.hide ();
        });
    }

    private float get_child_size (Clutter.Actor child) {
        if (horizontal) {
            float height;
            child.get_preferred_height (-1, null, out height);
            return height;
        } else {
            float width;
            child.get_preferred_width (-1, null, out width);
            return width;
        }
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
            if (!children_visible) {
                child.show ();
                var size = get_child_size (child);
                max = float.max (max, size);
                child.set (animation_prop, -size);
            }

            child.save_easing_state ();
            child.set_easing_duration (duration);
             child.set_easing_mode (Clutter.AnimationMode.EASE_IN_QUAD);
            child.set (animation_prop, 0.0f);
            child.restore_easing_state ();
        }

        if (resize) {
            save_easing_state ();
            set_easing_mode (Clutter.AnimationMode.EASE_IN_QUAD);
            set_easing_duration (duration);
            if (horizontal)
                height = max;
            else
                width = max;
            restore_easing_state ();
        }

        children_visible = true;
    }

    private void unreveal_child (Clutter.Actor child) {
        child.save_easing_state ();
        child.set_easing_duration (duration);
        child.set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUAD);
        child.set (animation_prop, -get_child_size (child));
        child.restore_easing_state ();
        child.get_transition (animation_prop).stopped.connect (() => {
            child.hide ();
            children_visible = false;
        });

    }

    public void unreveal () {
        if (!children_visible)
            return;

        bool found_child = false;
        foreach (var child in get_children ()) {
            found_child = true;
            unreveal_child (child);
        }

        if (resize) {
            save_easing_state ();
            set_easing_duration (duration);
            set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUAD);
            if (horizontal)
                height = 0.0f;
            else
                width = 0.0f;
            restore_easing_state ();
        }

        if (!found_child)
            children_visible = false;
    }
}
