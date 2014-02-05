// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.AuthNotification: Gd.Notification {
    public delegate void AuthFunc (string username, string password);

    public AuthNotification (string                         auth_string,
                             owned AuthFunc?                auth_func,
                             owned Notification.CancelFunc? cancel_func) {
        valign = Gtk.Align.START;
        timeout = -1;
        show_close_button = false;

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
            dismiss ();
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
        add (grid);

        show_all ();
    }
}
