// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.MenuBox: Gtk.Box {
    public signal void selected (Gtk.Widget widget);

    public class Item: Gtk.EventBox {
        private bool _in_item;
        private bool _selectable;
        private Gtk.Alignment alignment;

        private bool in_item {
            get { return _in_item; }
            set {
                _in_item = value;

                var flags = this.get_state_flags ();

                flags = flags & ~(Gtk.StateFlags.PRELIGHT | Gtk.StateFlags.ACTIVE);
                if (in_item && selectable)
                    flags |= Gtk.StateFlags.PRELIGHT;

                set_state_flags (flags, true);
            }
        }

        public bool selectable {
            get { return _selectable; }
            set {
                _selectable = value;
                can_focus = value;
            }
        }

        construct {
            get_style_context ().add_class ("menuitem");
            visible_window = false;

            alignment = new Gtk.Alignment (0.0f, 0.0f, 1.0f, 1.0f);
            child = alignment;

            enter_notify_event.connect (() => {
                in_item = true;
                return true;
            });

            leave_notify_event.connect (() => {
                in_item = false;
                return true;
            });
        }

        public Item (Gtk.Widget child, bool selectable = false) {
            alignment.add (child);
            this.selectable = selectable;
        }
    }

    public MenuBox (Gtk.Orientation orientation, int spacing = 0) {
        GLib.Object (orientation: orientation, spacing: spacing);
    }

    public override void add (Gtk.Widget widget) {
        var item  = widget as Item;

        if (item != null) {
            item.key_press_event.connect ((event) => {
                if (event.keyval == Gdk.Key.Return) {
                    selected (item);
                }
                return false;
            });
            item.button_press_event.connect (() => {
                item.grab_focus ();
                selected (item);
                return true;
            });
        }

        base.add (widget);
    }

    public override bool draw (Cairo.Context cr) {
        foreach (var child in get_children ()) {
            int position = 0;
            Gtk.Allocation child_allocation;
            Gtk.Allocation allocation;
            child_get (child, "position", ref position);
            bool last = get_children ().length () == (position + 1);

            child.get_allocation (out child_allocation);
            get_allocation (out allocation);
            child_allocation.x -= allocation.x;
            child_allocation.y -= allocation.y;

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
            ctxt.render_background (cr, child_allocation.x, child_allocation.y,
                                    child_allocation.width, child_allocation.height);
        }

        return base.draw (cr);
    }
}
