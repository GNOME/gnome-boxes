// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.Notificationbar: Gtk.Grid {
    public const int DEFAULT_TIMEOUT = 6;
    private const int MAX_NOTIFICATIONS = 5;

    GLib.List<Boxes.Notification> active_notifications;

    public Searchbar searchbar;

    construct {
        orientation = Gtk.Orientation.VERTICAL;
        valign = Gtk.Align.START;
        halign = Gtk.Align.CENTER;
        get_style_context ().add_class ("transparent-bg");

        show ();

        active_notifications = new GLib.List<Boxes.Notification> ();

        App.app.notify["page"].connect ( () => {
            foreach (var w in active_notifications) {
                var parent = w.get_parent () as Container;
                if (parent != null)
                    parent.remove (w);
                add_notification (w);
            }
        });
    }

    public Boxes.Notification display_for_action (string                          message,
                                                  string                          action_label,
                                                  owned Notification.OKFunc       action_func,
                                                  owned Notification.DismissFunc? ignore_func = null,
                                                  int                             timeout = DEFAULT_TIMEOUT) {
        return display (message, MessageType.INFO, action_label, (owned) action_func, (owned) ignore_func, timeout);
    }

    public Boxes.Notification display_error (string message, int timeout = DEFAULT_TIMEOUT) {
        return display (message, MessageType.ERROR, null, null, null, timeout);
    }

    public void dismiss_all () {
        foreach (var notification in active_notifications) {
            notification.dismiss ();
        }
    }

    private void add_notification (Widget w) {
        add (w);
    }

    private Boxes.Notification display (string                          message,
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

        var excess_notifications = (int) active_notifications.length () - MAX_NOTIFICATIONS + 1;

        for (var i = excess_notifications; i > 0; i--) {
            var last_notification = active_notifications.nth_data (active_notifications.length () - i)
                                    as Boxes.Notification;

            last_notification.dismiss ();
        }

        active_notifications.prepend (notification);

        notification.dismissed.connect ( () => {
            active_notifications.remove (notification);
        });

        add_notification (notification);

        return notification;
    }
}
