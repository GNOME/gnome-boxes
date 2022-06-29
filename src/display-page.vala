// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/display-page.ui")]
private class Boxes.DisplayPage: Gtk.Box {
    private const uint8 SCREEN_EDGE_WIDTH = 100;

    [GtkChild]
    public unowned DisplayToolbar toolbar;

    [GtkChild]
    public unowned Gtk.Label size_label;

    [GtkChild]
    public unowned Gtk.Box transfer_message_box;
    [GtkChild]
    private unowned EventBox event_box;
    [GtkChild]
    private unowned DisplayToolbar overlay_toolbar;
    [GtkChild]
    private unowned EventBox overlay_toolbar_box;
    public Boxes.TransferPopover transfer_popover;
    private uint toolbar_hide_id;
    private uint toolbar_show_id;
    private ulong cursor_id;
    private ulong widget_drag_motion_id = 0;
    private ulong transfer_message_box_drag_leave_id = 0;
    private ulong transfer_message_box_drag_motion_id = 0;

    private uint overlay_toolbar_invisible_timeout;
    private uint size_label_timeout;

    private AppWindow window;

    private Boxes.Display? display;
    private bool can_grab_mouse {
        get {
            return display != null ? display.can_grab_mouse : false;
        }
    }
    private bool mouse_grabbed {
        get {
            return display != null ? display.mouse_grabbed : false;
        }
    }
    private bool keyboard_grabbed {
        get {
            return display != null ? display.keyboard_grabbed : false;
        }
    }
    private ulong can_grab_mouse_id;
    private ulong mouse_grabbed_id;
    private ulong keyboard_grabbed_id;

    private int width = -1;
    private int height = -1;

    public void setup_ui (AppWindow window) {
        this.window = window;

        overlay_toolbar_invisible_timeout = AppWindow.TRANSITION_DURATION;
        event_box.set_events (EventMask.POINTER_MOTION_MASK | EventMask.SCROLL_MASK);

        window.window_state_event.connect ((event) => {
            update_toolbar_visible ();

            return false;
        });

        toolbar.bind_property ("title", overlay_toolbar, "title", BindingFlags.SYNC_CREATE);
        toolbar.bind_property ("subtitle", overlay_toolbar, "subtitle", BindingFlags.SYNC_CREATE);

        toolbar.setup_ui (window);
        overlay_toolbar.setup_ui (window);

        Gtk.TargetEntry[] target_list = {};
        Gtk.TargetEntry urilist_entry = { "text/uri-list", 0, 0 };
        target_list += urilist_entry;

        drag_dest_set (transfer_message_box, Gtk.DestDefaults.DROP, target_list, DragAction.ASK);
        transfer_popover = new Boxes.TransferPopover (window.topbar.display_toolbar);
    }

     private void update_toolbar_visible() {
         if (window.fullscreened && can_grab_mouse)
             toolbar.visible = true;
         else
             toolbar.visible = false;

         set_overlay_toolbar_visible (false);
     }

     public void add_transfer (Object transfer_task) {
        transfer_popover.add_transfer (transfer_task);
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

    public void update_subtitle () {
        var machine = window.current_item as Boxes.Machine;
        return_if_fail (machine != null);

        string? hint = null;
        if (can_grab_mouse) {
            if (mouse_grabbed)
                hint = _("Press (left) Ctrl+Alt to ungrab");
        } else if (keyboard_grabbed) {
            hint = _("Press & release (left) Ctrl+Alt to ungrab keyboard.");
        }
        toolbar.set_subtitle (hint);
    }

    public void show_display (Boxes.Display display, Widget widget) {
        replace_display (display, widget);

        window.below_bin.set_visible_child_name ("display-page");
        widget.grab_focus ();
    }

    public void replace_display (Boxes.Display display, Widget widget) {
        if (event_box.get_child () == widget)
            return;

        remove_display ();

        if (display.can_transfer_files) {
            widget_drag_motion_id = widget.drag_motion.connect (() => {
                transfer_message_box.visible = true;

                return true;
            });
            transfer_message_box_drag_motion_id = transfer_message_box.drag_motion.connect (() => {
                return true;
            });
            transfer_message_box_drag_leave_id = transfer_message_box.drag_leave.connect (() => {
                transfer_message_box.hide ();
            });
        }

        this.display = display;
        mouse_grabbed_id = display.notify["mouse-grabbed"].connect(() => {
            // In some cases this is sent inside size_allocate (see bug #692465)
            // which causes the label change queue_resize to be ignored
            // So we delay the update_subtitle call to an idle to work around this.
            Idle.add_full (Priority.HIGH, () => {
                update_subtitle ();
                return false;
            });
        });
        keyboard_grabbed_id = display.notify["keyboard-grabbed"].connect(() => {
            Idle.add_full (Priority.HIGH, () => {
                update_subtitle ();
                return false;
            });
        });
        update_toolbar_visible ();
        can_grab_mouse_id = display.notify["can-grab-mouse"].connect(() => {
            update_toolbar_visible ();
        });

        // FIXME: I got no clue why overlay toolbar won't become visible if we do this right away
        Idle.add (() => {
            update_toolbar_visible ();
            overlay_toolbar_invisible_timeout = 1000; // 1 seconds
            set_overlay_toolbar_visible (window.fullscreened);

            return false;
        });
        update_subtitle ();
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
    }

    public Widget? remove_display () {
        if (mouse_grabbed_id != 0) {
            display.disconnect (mouse_grabbed_id);
            mouse_grabbed_id = 0;
        }

        if (can_grab_mouse_id != 0) {
            display.disconnect (can_grab_mouse_id);
            can_grab_mouse_id = 0;
        }

        if (keyboard_grabbed_id != 0) {
            display.disconnect (keyboard_grabbed_id);
            keyboard_grabbed_id = 0;
        }
        display = null;

        var widget = event_box.get_child ();

        if (cursor_id != 0) {
            widget.get_window ().disconnect (cursor_id);
            cursor_id = 0;
        }

        if (transfer_message_box_drag_leave_id != 0) {
            transfer_message_box.disconnect (transfer_message_box_drag_leave_id);
            transfer_message_box_drag_leave_id = 0;
        }
        if (transfer_message_box_drag_motion_id != 0) {
            transfer_message_box.disconnect (transfer_message_box_drag_motion_id);
            transfer_message_box_drag_motion_id = 0;
        }

        if (widget != null) {
            if (widget_drag_motion_id != 0) {
                widget.disconnect (widget_drag_motion_id);
                widget_drag_motion_id = 0;
            }

            event_box.remove (widget);
        }

        return widget;
    }

    [GtkCallback]
    private bool on_event_box_event (Gdk.Event event) {
        if (window.fullscreened && event.type == EventType.MOTION_NOTIFY) {
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

        if (event_box.get_child () != null) {
            var child = event_box.get_child ();
            var offset_x = (get_allocated_width () - child.get_allocated_width ()) / 2.0;
            var offset_y = (get_allocated_height () - child.get_allocated_height ()) / 2.0;

            switch (event.get_event_type ()) {
            case Gdk.EventType.MOTION_NOTIFY:
                event.motion.x -= offset_x;
                event.motion.y -= offset_y;
                break;

            default:
                // Offset not needed or not possible
                break;
            }

            child.event (event);
        }

        return false;
    }

    [GtkCallback]
    private void on_size_allocate (Gtk.Allocation allocation) {
        if (width == allocation.width && height == allocation.height)
            return;

        width = allocation.width;
        height = allocation.height;

        // Translators: Showing size of widget as WIDTH×HEIGHT here.
        size_label.label = _("%d×%d").printf (allocation.width, allocation.height);

        Idle.add (() => {
            // Reason to do this in Idle is that Gtk+ doesn't like us showing
            // widgets from this signal handler.
            show_size_allocation ();

            return false;
        });
    }

    private void show_size_allocation () {
        size_label.visible = true;

        if (size_label_timeout != 0) {
            Source.remove (size_label_timeout);
            size_label_timeout = 0;
        }
        size_label_timeout = Timeout.add_seconds (3, () => {
            size_label.visible = false;
            size_label_timeout = 0;

            return false;
        });
    }
}
