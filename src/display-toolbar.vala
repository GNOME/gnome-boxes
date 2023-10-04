// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/display-toolbar.ui")]
private class Boxes.DisplayToolbar: Hdy.HeaderBar {
    public bool overlay { get; construct; }
    public bool handle_drag { get; construct; } // Handle drag events to (un)fulscreen the main window

    [GtkChild]
    private unowned Gtk.Image fullscreen_image;
    [GtkChild]
    private unowned Gtk.DrawingArea transfers_drawing_area;
    [GtkChild]
    public unowned Gtk.Button transfers_button;
    [GtkChild]
    private unowned Gtk.Button back;
    [GtkChild]
    private unowned Gtk.Button fullscreen;
    [GtkChild]
    private unowned Gtk.MenuButton menu_button;
    [GtkChild]
    private unowned Gtk.MenuButton keys_menu_button;

    private AppWindow window;

    private double _progress = 0;
    public double progress {
        get {
            return _progress;
        }
        set {
            if (!transfers_button.get_visible ())
                transfers_button.set_visible (true);

            _progress =  value;

            transfers_drawing_area.queue_draw ();
        }
    }

    public DisplayToolbar (bool overlay, bool handle_drag) {
        Object (overlay: overlay,
                handle_drag: handle_drag);
    }

    construct {
        add_events (Gdk.EventMask.POINTER_MOTION_MASK |
                    Gdk.EventMask.BUTTON_PRESS_MASK |
                    Gdk.EventMask.BUTTON_RELEASE_MASK);

        if (overlay) {
            get_style_context ().add_class (Gtk.STYLE_CLASS_TOOLBAR);
            get_style_context ().add_class (Gtk.STYLE_CLASS_OSD);
        } else {
            show_close_button = true;
        }

        if (!overlay) {
            back.get_style_context ().add_class (Gtk.STYLE_CLASS_RAISED);
            fullscreen.get_style_context ().add_class (Gtk.STYLE_CLASS_RAISED);
            menu_button.get_style_context ().add_class (Gtk.STYLE_CLASS_RAISED);
            keys_menu_button.get_style_context ().add_class (Gtk.STYLE_CLASS_RAISED);
        }
    }

    public void setup_ui (AppWindow window) {
        this.window = window;

        menu_button.popover = new ActionsPopover (window);
        App.app.notify["main-window"].connect (() => {
            back.visible = (window == App.app.main_window);
        });
        window.notify["ui-state"].connect (() => {
            if (window.ui_state == UIState.DISPLAY) {
                var actions_popover = menu_button.popover as ActionsPopover;
                actions_popover.update_for_item (window.current_item);
            }
        });
        keys_menu_button.popover = new KeysInputPopover (window);
        transfers_drawing_area.draw.connect (on_draw);

        window.notify["fullscreened"].connect_after ( () => {
            var a11y = fullscreen.get_accessible ();

            if (window.fullscreened) {
                fullscreen_image.icon_name = "view-restore-symbolic";
                a11y.accessible_name = _("Exit fullscreen");
            } else {
                fullscreen_image.icon_name = "view-fullscreen-symbolic";
                a11y.accessible_name = _("Fullscreen");
            }
        });
    }

    private bool on_draw (Widget da, Cairo.Context ctx) {

        var width = transfers_drawing_area.get_allocated_width ();
        var height = transfers_drawing_area.get_allocated_height ();

        ctx.set_line_join (Cairo.LineJoin.ROUND);

        var style_context = transfers_button.get_style_context ();
        var foreground = style_context.get_color (transfers_button.get_state_flags ());
        var background = foreground;

        background.alpha *= 0.3;
        ctx.set_source_rgba (background.red, background.green, background.blue, background.alpha);
        ctx.arc (width / 2, height / 2, height / 3, -Math.PI / 2, 3*Math.PI/2);
        ctx.fill ();

        ctx.move_to (width / 2, height / 2);
        ctx.set_source_rgba (foreground.red, foreground.green, foreground.blue, foreground.alpha);

        double radians = -Math.PI/2 + 2*Math.PI * _progress;
        ctx.arc (width / 2, height / 2, height / 3, -Math.PI / 2, radians);
        ctx.fill ();

        return true;
    }

    private bool button_down;
    private int button_down_x;
    private int button_down_y;
    private uint button_down_button;

    public override bool button_press_event (Gdk.EventButton event) {
        var res = base.button_press_event (event);
        if (!handle_drag)
            return res;

        Gdk.Event base_event = (Gdk.Event) event;

        if (!res && !base_event.triggers_context_menu ()) {
            button_down = true;
            button_down_button = event.button;
            button_down_x = (int) event.x;
            button_down_y = (int) event.y;
        }
        return res;
    }

    public override bool button_release_event (Gdk.EventButton event) {
        button_down = false;
        return base.button_press_event (event);
    }

    public override bool motion_notify_event (Gdk.EventMotion event) {
        if (!handle_drag)
            return base.motion_notify_event (event);

        if (button_down) {
            double dx = event.x - button_down_x;
            double dy = event.y - button_down_y;

            // Break out when the dragged distance is 40 pixels
            if (dx * dx + dy * dy > 40 * 40) {
                button_down = false;
                window.fullscreened = false;

                var window = get_toplevel () as Gtk.Window;
                int old_width;
                window.get_size (out old_width, null);

                ulong id = 0;
                id = App.app.notify["fullscreened"].connect ( () => {
                    int root_x, root_y, width;
                    window.get_position (out root_x, out root_y);
                    window.get_window ().get_geometry (null, null, out width, null);
                    window.begin_move_drag ((int) button_down_button,
                                            root_x + (int) ((button_down_x / (double) old_width) * width),
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

    [GtkCallback]
    private void on_back_clicked () {
        window.set_state (UIState.COLLECTION);
    }

    [GtkCallback]
    private void on_fullscreen_clicked () {
        window.fullscreened = !window.fullscreened;
    }
}
