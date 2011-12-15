// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.Notificationbar: GLib.Object {
    public Clutter.Actor actor { get; private set; }
    public static const float spacing = 60.0f;

    public delegate void ActionFunc ();
    public delegate void IgnoreFunc ();

    private App app;
    private InfoBar info_bar;
    private Label label;
    private Button action_button;

    private uint timeout_id;
    private ulong response_id;

    public Notificationbar (App app) {
        this.app = app;

        setup_action_notify ();
    }

    public void display (string            action_label,
                         string            action_message,
                         owned ActionFunc  action_func,
                         owned IgnoreFunc? ignore_func = null) {
        action_button.label = action_label;
        label.label = action_message;

        // Replace running notification, if any
        if (timeout_id != 0) {
            Source.remove (timeout_id);
            info_bar.disconnect (response_id);
        }

        timeout_id = Timeout.add_seconds (6, () => {
            info_bar.response (ResponseType.CANCEL);

            return false;
        });

        response_id = info_bar.response.connect ((response) => {
            hide ();

            Source.remove (timeout_id);
            info_bar.disconnect (response_id);
            timeout_id = 0;
            response_id = 0;

            if (response == ResponseType.OK)
                action_func ();
            else {
                if (ignore_func != null)
                    ignore_func ();
            }
        });

        show ();
    }

    private void setup_action_notify () {
        info_bar = new InfoBar ();
        info_bar.get_style_context ().add_class ("osd");
        info_bar.spacing = 120;
        info_bar.margin = 5;

        label = new Label ("");
        var content_area = info_bar.get_content_area () as Container;
        content_area.add (label);

        action_button = new Button ();
        info_bar.add_action_widget (action_button, ResponseType.OK);
        action_button.use_stock = true;

        var image = new Image.from_icon_name ("window-close-symbolic", IconSize.BUTTON);
        var close_button = new Button ();
        close_button.image = image;
        info_bar.add_action_widget (close_button, ResponseType.CANCEL);
        close_button.relief = ReliefStyle.NONE;
        close_button.halign = Align.START;

        var button_box = info_bar.get_action_area () as ButtonBox;
        button_box.orientation = Orientation.HORIZONTAL;
        button_box.set_child_non_homogeneous (close_button, true);
        info_bar.set_message_type (MessageType.INFO);

        info_bar.show_all ();

        actor = new GtkClutter.Actor.with_contents (info_bar);
        app.stage.add (actor);
        actor.hide ();
        actor.scale_y = 0f;
    }

    private void show () {
        actor.show ();
        actor.queue_redraw ();
        actor.animate (Clutter.AnimationMode.LINEAR, app.duration, "scale-y", 1f);
    }

    private void hide () {
        var animation = actor.animate (Clutter.AnimationMode.LINEAR, app.duration, "scale-y", 0f);
        animation.completed.connect (() => { actor.hide (); });
    }
}

