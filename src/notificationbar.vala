// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.Notificationbar: GLib.Object {
    public const int DEFAULT_TIMEOUT = 6;

    public Clutter.Actor actor { get { return gtk_actor; } }

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
        gtk_actor.x_expand = true;
        gtk_actor.y_expand = true;
        Gdk.RGBA transparent = { 0, 0, 0, 0};
        gtk_actor.get_widget ().override_background_color (0, transparent);

        App.app.notebook.notify["page"].connect ( () => {
            foreach (var w in active_notifications) {
                var parent = w.get_parent () as Container;
                if (parent != null)
                    parent.remove (w);
                add_notification (w);
            }
        });
    }

    public Gd.Notification display_for_action (string                         message,
                                               string                         action_label,
                                               owned Notification.OKFunc      action_func,
                                               owned Notification.CancelFunc? ignore_func = null,
                                               int                            timeout = DEFAULT_TIMEOUT) {
        return display (message, MessageType.INFO, action_label, (owned) action_func, (owned) ignore_func, timeout);
    }

    public Gd.Notification display_for_optional_auth (string                           broker_name,
                                                      owned AuthNotification.AuthFunc? auth_func,
                                                      owned Notification.CancelFunc?   cancel_func) {
        Notification.OKFunc next_auth_step = () => {
            var auth_string = "<span font-weight=\"bold\">" + _("Sign In to %s").printf(broker_name) + "</span>";
            display_for_auth (auth_string, (owned) auth_func, (owned) cancel_func);
        };
        return display_for_action (_("Not connected to %s").printf (broker_name),
                                   _("Sign In"),
                                   (owned) next_auth_step,
                                   (owned) cancel_func, -1);
    }

    public Gd.Notification display_for_auth (string                           auth_string,
                                             owned AuthNotification.AuthFunc? auth_func,
                                             owned Notification.CancelFunc?   cancel_func,
                                             bool                             need_username = true) {
        var notification = new Boxes.AuthNotification (auth_string,
                                                       (owned) auth_func,
                                                       (owned) cancel_func,
                                                       need_username);

        active_notifications.prepend (notification);

        notification.dismissed.connect ( () => {
            active_notifications.remove (notification);
        });

        add_notification (notification);

        return notification;
    }

    public Gd.Notification display_error (string message, int timeout = DEFAULT_TIMEOUT) {
        return display (message, MessageType.ERROR, null, null, null, timeout);
    }

    public void cancel () {
        // We destroy all active notifications, which will cause them to be dismissed
        while (active_notifications != null) {
            active_notifications.data.destroy ();
        }
    }

    private void add_notification (Widget w) {
        if (App.app.notebook.page == AppPage.MAIN)
            top_grid.attach (w, 0, 0, 1, 1);
        else
            App.app.display_page.add_notification (w);
    }

    private Gd.Notification display (string                         message,
                                     MessageType                    message_type,
                                     string?                        ok_label,
                                     owned Notification.OKFunc?     ok_func,
                                     owned Notification.CancelFunc? cancel_func,
                                     int                            timeout) {
        var notification = new Boxes.Notification (message,
                                                   message_type,
                                                   ok_label,
                                                   (owned) ok_func,
                                                   (owned) cancel_func,
                                                   timeout);

        active_notifications.prepend (notification);

        notification.dismissed.connect ( () => {
            active_notifications.remove (notification);
        });

        add_notification (notification);

        return notification;
    }
}
