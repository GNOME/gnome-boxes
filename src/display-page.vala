// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

private class Boxes.DisplayToolbar: Gd.MainToolbar {
    public DisplayToolbar () {
        get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        var back = add_button ("go-previous-symbolic", null, true) as Gtk.Button;
        back.clicked.connect ((button) => { App.app.ui_state = UIState.COLLECTION; });

        var fullscreen = add_button ("view-fullscreen-symbolic", null, false) as Gtk.Button;
        App.app.notify["fullscreen"].connect_after ( () => {
            var image = fullscreen.get_child() as Gtk.Image;
            if (App.app.fullscreen)
                image.icon_name = "view-restore-symbolic";
            else
                image.icon_name = "view-fullscreen-symbolic";
        });
        fullscreen.clicked.connect ((button) => { App.app.fullscreen = !App.app.fullscreen; });

        var props = add_button ("utilities-system-monitor-symbolic", null, false) as Gtk.Button;
        props.clicked.connect ((button) => { App.app.ui_state = UIState.PROPERTIES; });
    }
}

private class Boxes.DisplayPage: GLib.Object {
    public Widget widget { get { return box; } }

    private EventBox event_box;
    private Box box;
    private DisplayToolbar overlay_toolbar;
    private EventBox overlay_toolbar_box;
    private Grid notification_grid;
    private DisplayToolbar toolbar;
    private uint toolbar_hide_id;
    private uint toolbar_show_id;
    private ulong cursor_id;

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

    public DisplayPage () {
        event_box = new EventBox ();
        event_box.get_style_context ().add_class ("boxes-toplevel");
        event_box.set_events (EventMask.POINTER_MOTION_MASK | EventMask.SCROLL_MASK);
        event_box.above_child = true;
        event_box.event.connect ((event) => {
            if (App.app.fullscreen && event.type == EventType.MOTION_NOTIFY) {
                var y = event.motion.y;
                if (y <= 0 && toolbar_show_id == 0) {
                    toolbar_event_stop ();
                    if ((event.motion.state &
                         (ModifierType.SHIFT_MASK | ModifierType.CONTROL_MASK |
                          ModifierType.MOD1_MASK | ModifierType.SUPER_MASK |
                          ModifierType.HYPER_MASK | ModifierType.META_MASK |
                          ModifierType.BUTTON1_MASK | ModifierType.BUTTON2_MASK |
                          ModifierType.BUTTON3_MASK | ModifierType.BUTTON4_MASK |
                          ModifierType.BUTTON5_MASK)) == 0) {
                        toolbar_show_id = Timeout.add (App.app.duration, () => {
                            set_overlay_toolbar_visible (true);
                            toolbar_show_id = 0;
                            return false;
                        });
                    }
                } else if (y > 5 && toolbar_hide_id == 0) {
                    toolbar_event_stop ();
                    toolbar_hide_id = Timeout.add (App.app.duration, () => {
                        set_overlay_toolbar_visible (false);
                        toolbar_hide_id = 0;
                        return false;
                    });
                }
            }

            if (event.type == EventType.GRAB_BROKEN)
                return false;

            if (event_box.get_child () != null)
                event_box.get_child ().event (event);

            return false;
        });

        toolbar = new DisplayToolbar ();

        box = new Box (Orientation.VERTICAL, 0);
        box.pack_start (toolbar, false, false, 0);

        var grid = new Gtk.Grid ();
        App.app.window.window_state_event.connect ((event) => {
            update_toolbar_visible ();

            return false;
        });
        event_box.hexpand = true;
        event_box.vexpand = true;

        box.pack_start (grid, true, true, 0);

        overlay_toolbar = new DisplayToolbar ();
        overlay_toolbar_box = new EventBox ();
        overlay_toolbar_box.add (overlay_toolbar);
        overlay_toolbar_box.valign = Gtk.Align.START;
        overlay_toolbar_box.vexpand = false;

        notification_grid = new Grid ();
        notification_grid.valign = Gtk.Align.START;
        notification_grid.halign = Gtk.Align.CENTER;
        notification_grid.vexpand = true;

        grid.attach (event_box, 0, 0, 1, 2);
        grid.attach (overlay_toolbar_box, 0, 0, 1, 1);
        grid.attach (notification_grid, 0, 1, 1, 1);

        box.show_all ();
    }

    public void add_notification (Widget w) {
        notification_grid.attach (w, 0, 0, 1, 1);
    }

    public void get_size (out int width, out int height) {
        int tb_height;

        App.app.window.get_size (out width, out height);

        if (!App.app.fullscreen) {
            toolbar.get_preferred_height (null, out tb_height);
            height -= tb_height;
        }
    }

     private void update_toolbar_visible() {
         if (App.app.fullscreen && !can_grab_mouse)
             toolbar.visible = false;
         else
             toolbar.visible = true;

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

    public void show () {
        App.app.notebook.page = Boxes.AppPage.DISPLAY;
    }

    public void update_title () {
        var machine = App.app.current_item as Boxes.Machine;
        return_if_fail (machine != null);

        var title = machine.name;
        string? hint = null;
        if (grabbed)
            hint = _("(press Ctrl+Alt keys to ungrab)");

        overlay_toolbar.set_labels (title, hint);
        toolbar.set_labels (title, hint);
    }

    public void show_display (Boxes.Display display, Widget widget) {
        if (event_box.get_child () == widget)
            return;

        remove_display ();

        this.display = display;
        display_grabbed_id = display.notify["mouse-grabbed"].connect(() => {
            update_title ();
        });
        display_can_grab_id = display.notify["can-grab-mouse"].connect(() => {
            update_toolbar_visible ();
        });

        set_overlay_toolbar_visible (false);
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

        show ();
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

}
