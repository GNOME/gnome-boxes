// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.Notificationbar: Gtk.Grid {
    public const int DEFAULT_TIMEOUT = 6;

    GLib.List<Widget> active_notifications;

    public Searchbar searchbar;

    construct {
        orientation = Gtk.Orientation.VERTICAL;
        valign = Gtk.Align.START;
        halign = Gtk.Align.CENTER;
        get_style_context ().add_class ("transparent-bg");

        show ();

        active_notifications = new GLib.List<Widget> ();

        App.app.notify["page"].connect ( () => {
            foreach (var w in active_notifications) {
                var parent = w.get_parent () as Container;
                if (parent != null)
                    parent.remove (w);
                add_notification (w);
            }
        });
    }

    public Gd.Notification display_for_action (string                          message,
                                               string                          action_label,
                                               owned Notification.OKFunc       action_func,
                                               owned Notification.DismissFunc? ignore_func = null,
                                               int                             timeout = DEFAULT_TIMEOUT) {
        return display (message, MessageType.INFO, action_label, (owned) action_func, (owned) ignore_func, timeout);
    }

    public Gd.Notification display_for_optional_auth (string                           broker_name,
                                                      owned AuthNotification.AuthFunc? auth_func,
                                                      owned Notification.DismissFunc?  dismiss_func) {
        Notification.OKFunc next_auth_step = () => {
            var auth_string = "<span font-weight=\"bold\">" + _("Sign In to %s").printf(broker_name) + "</span>";
            display_for_auth (auth_string, (owned) auth_func, (owned) dismiss_func);
        };
        return display_for_action (_("Not connected to %s").printf (broker_name),
                                   _("Sign In"),
                                   (owned) next_auth_step,
                                   (owned) dismiss_func, -1);
    }

    public Gd.Notification display_for_auth (string                           auth_string,
                                             owned AuthNotification.AuthFunc? auth_func,
                                             owned Notification.DismissFunc?  dismiss_func,
                                             bool                             need_username = true) {
        var notification = new Boxes.AuthNotification (auth_string,
                                                       (owned) auth_func,
                                                       (owned) dismiss_func,
                                                       need_username,
                                                       searchbar);

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

    public void dismiss_all () {
        // We destroy all active notifications, which will cause them to be dismissed
        while (active_notifications != null) {
            active_notifications.data.destroy ();
        }
    }

    private void add_notification (Widget w) {
        add (w);
    }

    private Gd.Notification display (string                          message,
                                     MessageType                     message_type,
                                     string?                         ok_label,
                                     owned Notification.OKFunc?      ok_func,
                                     owned Notification.DismissFunc? dismiss_func,
                                     int                             timeout) {
        var notification = new Boxes.Notification (message,
                                                   message_type,
                                                   ok_label,
                                                   (owned) ok_func,
                                                   (owned) dismiss_func,
                                                   timeout);

        active_notifications.prepend (notification);

        notification.dismissed.connect ( () => {
            active_notifications.remove (notification);
        });

        add_notification (notification);

        return notification;
    }
}
