// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Clutter;

/* We overide all keyboard handling of GtkClutter.Embed, as it interfers
   with the key event propagation and thus focus navigation in gtk+.
   We also make the embed itself non-focusable, as we want to treat it
   like a container of Gtk+ widget rather than an edge widget which gets
   keyboard events.
   This means we will never get any Clutter key events, but that is
   fine, as all our keyboard input is into GtkClutterActors, and clutter
   is just used as a nice way of animating and rendering Gtk+ widgets
   and some non-active graphical things.
*/
private class Boxes.ClutterWidget: GtkClutter.Embed {
    public ClutterWidget () {
		set_can_focus (false);
    }
	public override bool key_press_event (Gdk.EventKey event) {
		return false;
	}
	public override bool key_release_event (Gdk.EventKey event) {
		return false;
	}
}
