// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

private class Boxes.DisplayToolbar: Gd.MainToolbar {
    private bool overlay;
    /* The left/right containers of Gd.MainToolbar are GtkGrids, which don't support first/last theming,
       which the osd css uses, so we need to add our own GtkBoxes instead. */
    private Gtk.Box leftbox;
    private Gtk.Box rightbox;

    public DisplayToolbar (bool overlay) {
        add_events (Gdk.EventMask.POINTER_MOTION_MASK);
        this.overlay = overlay;
        if (overlay)
            get_style_context ().add_class ("osd");
        else
            get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        int spacing = overlay ? 0 : 12;
        leftbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, spacing);
        add_widget (leftbox, true);

        rightbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, spacing);
        add_widget (rightbox, false);

        var back = add_image_button ("go-previous-symbolic", true);
        back.clicked.connect ((button) => { App.app.ui_state = UIState.COLLECTION; });

        var fullscreen = add_image_button ("view-fullscreen-symbolic", false);
        App.app.notify["fullscreen"].connect_after ( () => {
            var image = fullscreen.get_image() as Gtk.Image;
            if (App.app.fullscreen)
                image.icon_name = "view-restore-symbolic";
            else
                image.icon_name = "view-fullscreen-symbolic";
        });
        fullscreen.clicked.connect ((button) => { App.app.fullscreen = !App.app.fullscreen; });

        var props = add_image_button ("preferences-system-symbolic", false);
        props.clicked.connect ((button) => { App.app.ui_state = UIState.PROPERTIES; });
    }

    private Gtk.Button add_image_button (string icon_name, bool pack_start) {
        var button = new Gtk.Button ();
        var img = new Gtk.Image.from_icon_name (icon_name, Gtk.IconSize.MENU);
        img.show ();
        button.image = img;
        if (pack_start)
            leftbox.add (button);
        else
            rightbox.add (button);

        if (!overlay)
            button.get_style_context ().add_class ("raised");
        button.get_style_context ().add_class ("image-button");
        return button;
    }

    private bool button_down;
    private int button_down_x;
    private int button_down_y;
    private uint button_down_button;

    public override bool button_press_event (Gdk.EventButton event) {
        var res = base.button_press_event (event);

        // With the current GdkEvent bindings this is the only way to
        // upcast a GdkEventButton to a GdkEvent (which we need for
        // the triggerts_context_menu() method call.
        // TODO: Fix this when vala bindings are corrected
        Gdk.Event *base_event = (Gdk.Event *)(&event);

        if (!res && !base_event->triggers_context_menu ()) {
            button_down = true;
            button_down_button = event.button;
            button_down_x = (int)event.x;
            button_down_y = (int)event.y;
        }
        return res;
    }

    public override bool button_release_event (Gdk.EventButton event) {
        button_down = false;
        return base.button_press_event (event);
    }

    public override bool motion_notify_event (Gdk.EventMotion event) {
        if (button_down) {
            double dx = event.x - button_down_x;
            double dy = event.y - button_down_y;

            // Break out when the dragged distance is 40 pixels
            if (dx * dx + dy * dy > 40 * 40) {
                button_down = false;
                App.app.fullscreen = false;

                var window = get_toplevel () as Gtk.Window;
                int old_width;
                window.get_size (out old_width, null);

                ulong id = 0;
                id = App.app.notify["fullscreen"].connect ( () => {
                    int root_x, root_y, width;
                    window.get_position (out root_x, out root_y);
                    window.get_window ().get_geometry (null, null, out width, null);
                    window.begin_move_drag ((int)button_down_button,
                                            root_x + (int)((button_down_x / (double)old_width) * width),
                                            root_y + button_down_y,
                                            event.time);
                    App.app.disconnect (id);
                } );
            }
        }
        if (base.motion_notify_event != null)
            return base.motion_notify_event (event);
        return false;
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

        toolbar = new DisplayToolbar (false);

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

        overlay_toolbar = new DisplayToolbar (true);
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

}
