// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/express-install-row.ui")]
private class Boxes.ExpressInstallRow : Hdy.ExpanderRow {
    public signal void credentials_changed ();
    public bool ready_to_install {
        get {
            return !enabled || (username != null && username != "") &&
                    (password != null && password != "");
        }
    }

    public bool needs_password { get; set; default = true; }
    public bool needs_product_key {
        get {
            return _product_key_format != null;
        }
    }

    private string? _product_key_format = null;
    public string? product_key_format {
        set {
            _product_key_format = value;

            product_key_row.visible = value != null;
        }
    }

    public bool enabled {
        get {
            return expanded;
        }
    }

    public string username {
        get {
            return username_entry.get_text ();
        }
    }

    public string password {
        get {
            return password_entry.get_text ();
        }
    }

    public string product_key {
        get {
            return product_key_entry.get_text ();
        }
    }

    [GtkChild]
    protected unowned Gtk.Entry username_entry;
    [GtkChild]
    protected unowned Gtk.Entry password_entry;
    [GtkChild]
    public unowned Hdy.ActionRow product_key_row;
    [GtkChild]
    public unowned Gtk.Entry product_key_entry;

    [GtkCallback]
    private void on_entry_changed () {
        credentials_changed ();
    }

    [GtkCallback]
    private void on_secondary_icon_clicked () {
        password_entry.visibility = !password_entry.visibility;

        password_entry.secondary_icon_name = password_entry.visibility ?
                                             "eye-open-negative-filled-symbolic" :
                                             "eye-not-looking-symbolic";
    }
}
