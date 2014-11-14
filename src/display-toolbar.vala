// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/display-toolbar.ui")]
private class Boxes.DisplayToolbar: Gtk.HeaderBar {
    public bool overlay { get; construct; }
    public bool handle_drag { get; construct; } // Handle drag events to (un)fulscreen the main window

    [GtkChild]
    private Gtk.Image fullscreen_image;
    [GtkChild]
    private Gtk.Button back;
    [GtkChild]
    private Gtk.Button fullscreen;
    [GtkChild]
    private Gtk.Button props;

    private AppWindow window;

    public DisplayToolbar (bool overlay, bool handle_drag) {
        Object (overlay: overlay,
                handle_drag: handle_drag);
    }

    construct {
        add_events (Gdk.EventMask.POINTER_MOTION_MASK |
                    Gdk.EventMask.BUTTON_PRESS_MASK |
                    Gdk.EventMask.BUTTON_RELEASE_MASK);

        if (overlay) {
            get_style_context ().add_class ("toolbar");
            get_style_context ().add_class ("osd");
        } else {
            show_close_button = true;
        }

        if (!overlay) {
            back.get_style_context ().add_class ("raised");
            fullscreen.get_style_context ().add_class ("raised");
            props.get_style_context ().add_class ("raised");
        }

        App.app.notify["fullscreened"].connect_after ( () => {
            if (window.fullscreened)
                fullscreen_image.icon_name = "view-restore-symbolic";
            else
                fullscreen_image.icon_name = "view-fullscreen-symbolic";
        });
    }

    public void setup_ui (AppWindow window) {
        this.window = window;

        App.app.notify["main-window"].connect (() => {
            back.visible = (window == App.app.main_window);
        });
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

    [GtkCallback]
    private void on_props_clicked () {
        window.set_state (UIState.PROPERTIES);
    }
}
