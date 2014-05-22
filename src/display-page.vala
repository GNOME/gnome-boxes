// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/display-page.ui")]
private class Boxes.DisplayPage: Gtk.Box {
    private const uint8 SCREEN_EDGE_WIDTH = 80;

    [GtkChild]
    public DisplayToolbar toolbar;

    [GtkChild]
    private EventBox event_box;
    [GtkChild]
    private DisplayToolbar overlay_toolbar;
    [GtkChild]
    private EventBox overlay_toolbar_box;
    private uint toolbar_hide_id;
    private uint toolbar_show_id;
    private ulong cursor_id;

    private uint overlay_toolbar_invisible_timeout;

    private Boxes.Display? display;
    private bool can_grab_mouse {
        get {
            return display != null ? display.can_grab_mouse : false;
        }
    }
    private bool grabbed {
        get {
            return display != null ? display.mouse_grabbed : false;
        }
    }
    private ulong display_can_grab_id;
    private ulong display_grabbed_id;

    public void setup_ui () {
        overlay_toolbar_invisible_timeout = AppWindow.TRANSITION_DURATION;
        event_box.set_events (EventMask.POINTER_MOTION_MASK | EventMask.SCROLL_MASK);

        App.window.window_state_event.connect ((event) => {
            update_toolbar_visible ();

            return false;
        });

        toolbar.bind_property ("title", overlay_toolbar, "title", BindingFlags.SYNC_CREATE);
        toolbar.bind_property ("subtitle", overlay_toolbar, "subtitle", BindingFlags.SYNC_CREATE);
    }

     private void update_toolbar_visible() {
         if (App.window.fullscreened && can_grab_mouse)
             toolbar.visible = true;
         else
             toolbar.visible = false;

         set_overlay_toolbar_visible (false);
     }

     private void set_overlay_toolbar_visible(bool visible) {
        if (visible && toolbar.visible) {
            debug ("toolbar is visible, don't show overlay toolbar");
            return;
        }

        overlay_toolbar_box.visible = visible;
    }

    ~DisplayPage () {
        toolbar_event_stop ();
    }

    private void toolbar_event_stop () {
        if (toolbar_hide_id != 0)
            GLib.Source.remove (toolbar_hide_id);
        toolbar_hide_id = 0;
        if (toolbar_show_id != 0)
            GLib.Source.remove (toolbar_show_id);
        toolbar_show_id = 0;
    }

    public void update_title () {
        var machine = App.app.current_item as Boxes.Machine;
        return_if_fail (machine != null);

        var title = machine.name;
        string? hint = null;
        if (grabbed)
            hint = _("(press [left] Ctrl+Alt keys to ungrab)");

        toolbar.set_title (title);
        toolbar.set_subtitle (hint);
    }

    public void show_display (Boxes.Display display, Widget widget) {
        if (event_box.get_child () == widget)
            return;

        remove_display ();

        this.display = display;
        display_grabbed_id = display.notify["mouse-grabbed"].connect(() => {
            // In some cases this is sent inside size_allocate (see bug #692465)
            // which causes the label change queue_resize to be ignored
            // So we delay the update_title call to an idle to work around this.
            Idle.add_full (Priority.HIGH, () => {
                update_title ();
                return false;
            });
        });
        update_toolbar_visible ();
        display_can_grab_id = display.notify["can-grab-mouse"].connect(() => {
            update_toolbar_visible ();
        });

        // FIXME: I got no clue why overlay toolbar won't become visible if we do this right away
        Idle.add (() => {
            update_toolbar_visible ();
            overlay_toolbar_invisible_timeout = 1000; // 1 seconds
            set_overlay_toolbar_visible (App.window.fullscreened);

            return false;
        });
        update_title ();
        widget.set_events (widget.get_events () & ~Gdk.EventMask.POINTER_MOTION_MASK);
        event_box.add (widget);
        event_box.show_all ();

        ulong draw_id = 0;
        draw_id = widget.draw.connect (() => {
            widget.disconnect (draw_id);

            cursor_id = widget.get_window ().notify["cursor"].connect (() => {
                event_box.get_window ().set_cursor (widget.get_window ().cursor);
            });

            return false;
        });

        App.window.below_bin.set_visible_child_name ("display-page");

        widget.grab_focus ();
    }

    public Widget? remove_display () {
        if (display_grabbed_id != 0) {
            display.disconnect (display_grabbed_id);
            display_grabbed_id = 0;
        }

        if (display_can_grab_id != 0) {
            display.disconnect (display_can_grab_id);
            display_can_grab_id = 0;
        }

        var widget = event_box.get_child ();

        if (cursor_id != 0) {
            widget.get_window ().disconnect (cursor_id);
            cursor_id = 0;
        }

        if (widget != null)
            event_box.remove (widget);

        return widget;
    }

    [GtkCallback]
    private bool on_event_box_event (Gdk.Event event) {
        if (App.window.fullscreened && event.type == EventType.MOTION_NOTIFY) {
            var x = event.motion.x;
            var y = event.motion.y;
            if (x >= SCREEN_EDGE_WIDTH && x <= (get_allocated_width () - SCREEN_EDGE_WIDTH) &&
                y <= 0 && toolbar_show_id == 0) {
                toolbar_event_stop ();
                if ((event.motion.state &
                     (ModifierType.SHIFT_MASK | ModifierType.CONTROL_MASK |
                      ModifierType.MOD1_MASK | ModifierType.SUPER_MASK |
                      ModifierType.HYPER_MASK | ModifierType.META_MASK |
                      ModifierType.BUTTON1_MASK | ModifierType.BUTTON2_MASK |
                      ModifierType.BUTTON3_MASK | ModifierType.BUTTON4_MASK |
                      ModifierType.BUTTON5_MASK)) == 0) {
                    toolbar_show_id = Timeout.add (AppWindow.TRANSITION_DURATION, () => {
                        set_overlay_toolbar_visible (true);
                        toolbar_show_id = 0;
                        return false;
                    });
                }
            } else if (y > 5 && toolbar_hide_id == 0) {
                toolbar_event_stop ();
                toolbar_hide_id = Timeout.add (overlay_toolbar_invisible_timeout, () => {
                    set_overlay_toolbar_visible (false);
                    toolbar_hide_id = 0;
                    overlay_toolbar_invisible_timeout = AppWindow.TRANSITION_DURATION;
                    return false;
                });
            }
        }

        if (event.type == EventType.GRAB_BROKEN)
            return false;

        if (event_box.get_child () != null)
            event_box.get_child ().event (event);

        return false;
    }
}
