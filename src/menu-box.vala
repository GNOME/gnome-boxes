// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.MenuBox: Gtk.Box {
    public signal void selected (Gtk.Widget widget);

    private class Child {
        public Gtk.Widget widget;
        public bool in_item;

        public Child (Gtk.Widget widget) {
            this.widget = widget;
        }

        public void update_state () {
            var flags = widget.get_state_flags ();

            flags = flags & ~(Gtk.StateFlags.PRELIGHT | Gtk.StateFlags.ACTIVE);
            if (in_item)
                flags |= Gtk.StateFlags.PRELIGHT;

            widget.set_state_flags (flags, true);
        }
    }

    private new int spacing;
    private HashTable<Gtk.Widget, Child> children;
    construct {
        children = new HashTable<Gtk.Widget, Child> (GLib.direct_hash, GLib.direct_equal);
    }

    public MenuBox (Gtk.Orientation orientation, int spacing = 10) {
        GLib.Object (orientation: orientation);
        this.spacing = spacing;
    }

    public override void remove (Gtk.Widget widget) {
        children.remove (widget);
        base.remove (widget);
    }

    public override void add (Gtk.Widget widget) {
        var eventbox = new Gtk.EventBox ();
        eventbox.get_style_context ().add_class ("menuitem");
        eventbox.visible_window = false;
        eventbox.can_focus = true;

        var child = new Child (eventbox);
        children.insert (eventbox, child);

        eventbox.enter_notify_event.connect (() => {
            child.in_item = true;
            child.update_state ();
            return true;
        });

        eventbox.leave_notify_event.connect (() => {
            child.in_item = false;
            child.update_state ();
            return true;
        });
        eventbox.button_press_event.connect (() => {
            eventbox.grab_focus ();
            selected (widget);
            return true;
        });

        var alignment = new Gtk.Alignment (0.0f, 0.0f, 1.0f, 1.0f);
        alignment.add (widget);
        alignment.margin_top = 10;
        alignment.margin_bottom = 10;
        eventbox.add (alignment);
        base.add (eventbox);
    }

    public override bool draw (Cairo.Context cr) {
        foreach (var child in get_children ()) {
            int position = 0;
            Gtk.Allocation allocation;
            child_get (child, "position", ref position);
            bool last = get_children ().length () == (position + 1);

            child.get_allocation (out allocation);

            var ctxt = child.get_style_context ();
            Gtk.JunctionSides junction = 0;

            if (orientation == Gtk.Orientation.VERTICAL) {
                if (!last)
                    junction |= Gtk.JunctionSides.BOTTOM;
                if (position != 0)
                    junction |= Gtk.JunctionSides.TOP;
            } else {
                if (!last)
                    junction |= Gtk.JunctionSides.RIGHT;
                if (position != 0)
                    junction |= Gtk.JunctionSides.LEFT;
            }

            ctxt.set_state (child.get_state_flags ());
            ctxt.set_junction_sides (junction);
            ctxt.render_background (cr, allocation.x, allocation.y,
                                    allocation.width, allocation.height);
        }

        return base.draw (cr);
    }
}
