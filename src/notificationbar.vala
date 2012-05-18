// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.Notificationbar: GLib.Object {
    public Clutter.Actor actor { get; private set; }
    public static const float spacing = 60.0f;

    public delegate void OKFunc ();
    public delegate void CancelFunc ();

    private App app;
    private InfoBar info_bar;
    private Label message_label;
    private Button ok_button;

    private uint timeout_id;
    private ulong response_id;

    public Notificationbar (App app) {
        this.app = app;

        setup_action_notify ();
    }

    public void display_for_action (string            message,
                                    string            action_label,
                                    owned OKFunc      action_func,
                                    owned CancelFunc? ignore_func = null) {
        display (message, MessageType.INFO, action_label, (owned) action_func, (owned) ignore_func);
    }

    public void display_error (string message) {
        display (message, MessageType.ERROR);
    }

    public void cancel () {
        info_bar.response (ResponseType.CANCEL);
    }

    private void display (string            message,
                          MessageType       message_type,
                          string?           ok_label = null,
                          owned OKFunc?     ok_func = null,
                          owned CancelFunc? cancel_func = null) {
        if (ok_label != null) {
            ok_button.label = ok_label;
            info_bar.spacing = 120;
            ok_button.show ();
        } else {
            info_bar.spacing = 60;
            ok_button.hide ();
        }
        message_label.label = message;
        info_bar.message_type = message_type;

        // Replace running notification, if any
        if (timeout_id != 0) {
            Source.remove (timeout_id);
            info_bar.disconnect (response_id);
        }

        add_timeout ();

        response_id = info_bar.response.connect ((response) => {
            hide ();

            Source.remove (timeout_id);
            info_bar.disconnect (response_id);
            timeout_id = 0;
            response_id = 0;

            if (response == ResponseType.OK) {
                if (ok_func != null)
                    ok_func ();
            } else {
                if (cancel_func != null)
                    cancel_func ();
            }
        });

        show ();
    }

    private void add_timeout () {
        if (!app.window.is_active) {
            // Don't timeout before user gets a chance to see's the notification
            ulong active_id = 0;
            active_id = app.window.notify["is-active"].connect (() => {
                add_timeout ();
                app.window.disconnect (active_id);
            });

            return;
        }

        timeout_id = Timeout.add_seconds (6, () => {
            info_bar.response (ResponseType.CANCEL);

            return false;
        });
    }

    private void setup_action_notify () {
        info_bar = new InfoBar ();
        info_bar.get_style_context ().add_class ("osd");
        info_bar.margin = 5;

        message_label = new Label ("");
        var content_area = info_bar.get_content_area () as Container;
        content_area.add (message_label);

        ok_button = new Button ();
        info_bar.add_action_widget (ok_button, ResponseType.OK);
        ok_button.use_stock = true;

        var image = new Image.from_icon_name ("window-close-symbolic", IconSize.BUTTON);
        var close_button = new Button ();
        close_button.image = image;
        info_bar.add_action_widget (close_button, ResponseType.CANCEL);
        close_button.relief = ReliefStyle.NONE;
        close_button.halign = Align.START;

        var button_box = info_bar.get_action_area () as ButtonBox;
        button_box.orientation = Orientation.HORIZONTAL;
        button_box.set_child_non_homogeneous (close_button, true);

        info_bar.show_all ();

        actor = new GtkClutter.Actor.with_contents (info_bar);
        app.stage.add (actor);
        actor.hide ();
        actor.scale_y = 0f;
    }

    private void show () {
        app.stage.set_child_above_sibling (actor, null);
        actor.show ();
        actor.queue_redraw ();
        actor.animate (Clutter.AnimationMode.LINEAR, app.duration, "scale-y", 1f);
    }

    private void hide () {
        var animation = actor.animate (Clutter.AnimationMode.LINEAR, app.duration, "scale-y", 0f);
        animation.completed.connect (() => { actor.hide (); });
    }
}

