// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.Notificationbar: GLib.Object {
    public const int DEFAULT_TIMEOUT = 6;

    public Clutter.Actor actor { get { return gtk_actor; } }

    public delegate void OKFunc ();
    public delegate void CancelFunc ();
    public delegate void AuthenticateFunc (string username, string password);

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

    public Gd.Notification display_for_action (string            message,
                                               string            action_label,
                                               owned OKFunc      action_func,
                                               owned CancelFunc? ignore_func = null,
                                               int               timeout = DEFAULT_TIMEOUT) {
        return display (message, MessageType.INFO, action_label, (owned) action_func, (owned) ignore_func, timeout);
    }

    public Gd.Notification display_for_authentication (string broker_name,
                                                       owned AuthenticateFunc? auth_func,
                                                       owned CancelFunc? cancel_func) {
        Notificationbar.OKFunc next_auth_step = () => {
            display_for_auth_next (broker_name, (owned) auth_func, (owned) cancel_func);
        };
        return display_for_action (_("Not connected to %s").printf (broker_name),
                                   _("Sign In"),
                                   (owned) next_auth_step,
                                   (owned) cancel_func, -1);
    }

    private Gd.Notification display_for_auth_next (string auth_string,
                                                   owned AuthenticateFunc? auth_func,
                                                   owned CancelFunc? cancel_func) {
        var notification = new Gd.Notification ();
        notification.valign = Gtk.Align.START;
        notification.timeout = -1;
        notification.show_close_button = false;

        active_notifications.prepend (notification);

        notification.dismissed.connect ( () => {
            active_notifications.remove (notification);
        });

        var title_label = new Gtk.Label (null);
        string title_str = "<span font-weight=\"bold\">" + _("Sign In to %s").printf(auth_string) + "</span>";

        title_label.set_markup (title_str);
        title_label.halign = Gtk.Align.START;
        title_label.margin_bottom = 18;

        var username_label = new Gtk.Label.with_mnemonic (_("_Username"));
        var username_entry = new Gtk.Entry ();
        username_entry.focus_in_event.connect ( () => {
            App.app.searchbar.enable_key_handler = false;
            return false;
        });
        username_entry.focus_out_event.connect ( () => {
            App.app.searchbar.enable_key_handler = true;
            return false;
        });
        username_entry.map.connect ( () => {
            username_entry.grab_focus ();
        });
        username_label.mnemonic_widget = username_entry;
        username_label.margin_left = 12;
        var password_label = new Gtk.Label.with_mnemonic (_("_Password"));
        var password_entry = new Gtk.Entry ();
        password_entry.visibility = false;
        password_entry.focus_in_event.connect ( () => {
            App.app.searchbar.enable_key_handler = false;
            return false;
        });
        password_entry.focus_out_event.connect ( () => {
            App.app.searchbar.enable_key_handler = true;
            return false;
        });
        password_label.mnemonic_widget = password_entry;
        password_label.margin_left = 12;

        var auth_button = new Button.from_stock (_("Sign In"));
        auth_button.halign = Gtk.Align.END;

        auth_button.clicked.connect ( () => {
            if (auth_func != null)
                 auth_func (username_entry.get_text (), password_entry.get_text ());
            notification.dismiss ();
        });

        username_entry.activate.connect (() => {
            password_entry.grab_focus ();
        });
        password_entry.activate.connect (() => {
            auth_button.activate ();
        });

        var grid = new Gtk.Grid ();
        grid.column_spacing = 12;
        grid.row_spacing = 6;
        grid.border_width = 6;
        grid.attach (title_label, 0, 0, 2, 1);
        grid.attach (username_label, 0, 1, 1, 1);
        grid.attach (username_entry, 1, 1, 1, 1);
        grid.attach (password_label, 0, 2, 1, 1);
        grid.attach (password_entry, 1, 2, 1, 1);
        grid.attach (auth_button, 1, 3, 1, 1);
        notification.add (grid);

        add_notification (notification);
        notification.show_all ();

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

    private Gd.Notification display (string            message,
                                     MessageType       message_type,
                                     string?           ok_label,
                                     owned OKFunc?     ok_func,
                                     owned CancelFunc? cancel_func,
                                     int               timeout) {
        var notification = new Gd.Notification ();
        notification.valign = Gtk.Align.START;
        notification.timeout = timeout;

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
            var ok_button = new Button.with_mnemonic (ok_label);
            ok_button.halign = Gtk.Align.END;
            grid.add (ok_button);

            ok_button.clicked.connect ( () => {
                ok_pressed = true;
                if (ok_func != null)
                    ok_func ();
                notification.dismiss ();
            });
        }

        add_notification (notification);
        notification.show_all ();

        return notification;
    }
}
