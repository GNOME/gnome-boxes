// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/auth-notification.ui")]
private class Boxes.AuthNotification: Gd.Notification {
    public delegate void AuthFunc (string username, string password);

    [GtkChild]
    private Gtk.Label title_label;
    [GtkChild]
    private Gtk.Entry username_entry;
    [GtkChild]
    private Gtk.Entry password_entry;
    [GtkChild]
    private Gtk.Button auth_button;

    private AuthFunc? auth_func;

    public AuthNotification (string                         auth_string,
                             owned AuthFunc?                auth_func,
                             owned Notification.CancelFunc? cancel_func) {
        show_close_button = false; // FIXME: Seems setting this from .UI file doesn't work
        title_label.label = "<span font-weight=\"bold\">" + _("Sign In to %s").printf(auth_string) + "</span>";

        this.auth_func = (owned) auth_func;
    }

    [GtkCallback]
    private bool on_entry_focus_in_event () {
        App.app.searchbar.enable_key_handler = false;

        return false;
    }

    [GtkCallback]
    private bool on_entry_focus_out_event () {
        App.app.searchbar.enable_key_handler = true;

        return false;
    }

    [GtkCallback]
    private void on_username_entry_map () {
        username_entry.grab_focus ();
    }

    [GtkCallback]
    private void on_username_entry_activated () {
        password_entry.grab_focus ();
    }

    [GtkCallback]
    private void on_password_entry_activated () {
        auth_button.activate ();
    }

    [GtkCallback]
    private void on_auth_button_clicked () {
        if (auth_func != null)
            auth_func (username_entry.get_text (), password_entry.get_text ());
        dismiss ();
    }
}
