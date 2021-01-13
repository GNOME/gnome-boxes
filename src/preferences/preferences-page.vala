// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.PreferencesNotification: Gtk.InfoBar {
    private Notification.DismissFunc? dismiss_func;

    public PreferencesNotification (string message,
                                    string action_label,
                                    owned Notification.OKFunc ok_func,
                                    owned Notification.DismissFunc? ignore_func = null) {
        dismiss_func = ignore_func;

        var label = new Gtk.Label (message) {
            hexpand = true,
            halign = Gtk.Align.START
        };
        var button = new Gtk.Button.with_label (action_label);
        button.clicked.connect (() => {
            if (ok_func != null)
                ok_func ();

            destroy ();
        });

        get_content_area ().add (label);
        get_content_area ().add (button);
    }

    public void dismiss () {
        if (dismiss_func != null)
            dismiss_func ();
    }
}

private class Boxes.PreferencesPage: Hdy.PreferencesPage {
    protected PreferencesNotification active_notification = null;

    protected void display_notification (string message,
                                         string action_label,
                                         owned Notification.OKFunc       ok_func,
                                         owned Notification.DismissFunc? ignore_func = null) {
        if (active_notification != null) {
            active_notification.dismiss ();
        }

        active_notification = new PreferencesNotification (message, action_label, ok_func, ignore_func);

        var box = get_parent ().get_parent () as Gtk.Container;
        box.add_with_properties (active_notification, "position", 0, null);

        active_notification.show_all ();
    }

    ~PreferencesPage () {
        if (active_notification != null)
            active_notification.dismiss ();
    }
}
