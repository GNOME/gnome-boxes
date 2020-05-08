// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/auth-notification.ui")]
private class Boxes.AuthNotification: Gtk.Revealer {
    public signal void dismissed ();

    public delegate void AuthFunc (string username, string password);

    [GtkChild]
    private Gtk.Label title_label;
    [GtkChild]
    private Gtk.Label username_label;
    [GtkChild]
    private Gtk.Entry username_entry;
    [GtkChild]
    private Gtk.Entry password_entry;
    [GtkChild]
    private Gtk.Button auth_button;

    private AuthFunc? auth_func;
    private bool auth_pressed;

    private Searchbar searchbar;

    public AuthNotification (string                          auth_string,
                             owned AuthFunc?                 auth_func,
                             owned Notification.DismissFunc? dismiss_func,
                             bool                            need_username,
                             Searchbar                       searchbar) {
        /*
         * Templates cannot set construct properties, so
         * lets use the respective property setter method.
         */
        set_reveal_child (true);

        title_label.label = auth_string;

        dismissed.connect (() => {
            if (!auth_pressed && dismiss_func != null)
                dismiss_func ();
        });

        username_label.visible = need_username;
        username_entry.visible = need_username;

        this.auth_func = (owned) auth_func;

        this.searchbar = searchbar;
    }

    [GtkCallback]
    private bool on_entry_focus_in_event () {
        searchbar.enable_key_handler = false;

        return false;
    }

    [GtkCallback]
    private bool on_entry_focus_out_event () {
        searchbar.enable_key_handler = true;

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
    private void on_password_entry_map () {
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
        auth_pressed = true;

        dismiss ();
    }

    public void dismiss () {
        set_reveal_child (false);
        dismissed ();
    }
}
