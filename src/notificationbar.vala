// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.Notificationbar: GLib.Object {
    public Clutter.Actor actor { get { return gtk_actor; } }

    public delegate void OKFunc ();
    public delegate void CancelFunc ();

    private GtkClutter.Actor gtk_actor;
    private Gtk.Grid top_grid;

    GLib.List<Widget> active_notifications;

    public Notificationbar () {
        active_notifications = new GLib.List<Widget> ();

        top_grid = new Gtk.Grid ();
        top_grid.show ();

        gtk_actor = new GtkClutter.Actor.with_contents (top_grid);
        gtk_actor.name = "notificationbar";
        gtk_actor.x_align = Clutter.ActorAlign.CENTER;
        gtk_actor.y_align = Clutter.ActorAlign.START;
        Gdk.RGBA transparent = { 0, 0, 0, 0};
        gtk_actor.get_widget ().override_background_color (0, transparent);

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
        // We destroy all active notifications, which will cause them to be dismissed
        while (active_notifications != null)
            active_notifications.data.destroy ();
    }

    private void add_notification (Widget w) {
        top_grid.attach (w, 0, 0, 1, 1);
    }

    private void display (string            message,
                          MessageType       message_type,
                          string?           ok_label = null,
                          owned OKFunc?     ok_func = null,
                          owned CancelFunc? cancel_func = null) {
        var notification = new Gd.Notification ();
        notification.valign = Gtk.Align.START;
        notification.timeout = 6;

        active_notifications.prepend (notification);

        bool ok_pressed = false;
        notification.dismissed.connect ( () => {
            if (!ok_pressed && cancel_func != null)
                cancel_func ();
            active_notifications.remove (notification);
        });

        var grid = new Gtk.Grid ();
        grid.set_orientation (Gtk.Orientation.HORIZONTAL);
        grid.margin_left = 12;
        grid.margin_right = 12;
        grid.column_spacing = 12;
        grid.valign = Gtk.Align.CENTER;
        notification.add (grid);

        var message_label = new Label (message);
        grid.add (message_label);

        if (ok_label != null) {
            var ok_button = new Button.from_stock (ok_label);
            ok_button.halign = Gtk.Align.END;
            grid.add (ok_button);

            ok_button.pressed.connect ( () => {
                ok_pressed = true;
                if (ok_func != null)
                    ok_func ();
                notification.dismiss ();
            });
        }

        add_notification (notification);
        notification.show_all ();
    }
}
