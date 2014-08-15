// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/unattended-setup-box.ui")]
private class Boxes.UnattendedSetupBox : Gtk.Box {
    public bool ready_for_express {
        get {
            return username != "" &&
                   (product_key_format == null ||
                    product_key_entry.text_length == product_key_format.length);
        }
    }

    public bool ready_to_create {
        get {
            return !express_toggle.active || ready_for_express;
        }
    }

    public bool express_install {
        get {
            return express_toggle.active;
        }

        set {
            express_toggle.active = value;
        }
    }

    public string username {
        get { return username_entry.text; }
    }

    public string password {
        owned get { return password_entry.text; }
    }

    public string hidden_password {
        owned get {
            if (password_entry.text.length > 0) {
                var str = "";
                for (var i = 0; i < password_entry.text_length; i++)
                    str += password_entry.get_invisible_char ().to_string ();

                return str;
            } else
                return _("no password");
        }
    }

    public string product_key {
        owned get {
            return (product_key_entry != null)? product_key_entry.text : null;
        }
    }

    public string avatar_path {
        set {
            try {
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale (value, 64, 64, true);
                user_avatar.pixbuf = pixbuf;
            } catch (GLib.Error error) {
                debug ("Failed to load user avatar file '%s': %s", value, error.message);
            }
        }
    }

    public signal void user_wants_to_create (); // User wants to already create the VM

    [GtkChild]
    private Gtk.Grid setup_grid;
    [GtkChild]
    private Gtk.Label express_label;
    [GtkChild]
    private Gtk.Switch express_toggle;
    [GtkChild]
    private Gtk.Image user_avatar;
    [GtkChild]
    private Gtk.Entry username_entry;
    [GtkChild]
    private Gtk.Notebook password_notebook;
    [GtkChild]
    private Gtk.Entry password_entry;
    [GtkChild]
    private Gtk.Label product_key_label;
    [GtkChild]
    private Gtk.Entry product_key_entry;

    private string? product_key_format;

    public UnattendedSetupBox (bool live, string? product_key_format) {
        this.product_key_format = product_key_format;
        express_toggle.active = !live;
        username_entry.text = Environment.get_user_name ();

        if (product_key_format != null) {
            product_key_label.visible = true;

            product_key_entry.visible = true;
            product_key_entry.width_chars = product_key_format.length;
            product_key_entry.max_length = product_key_format.length;
        }

        foreach (var child in setup_grid.get_children ())
            if (child != express_label && child != express_toggle)
                express_toggle.bind_property ("active", child, "sensitive", BindingFlags.SYNC_CREATE);
    }

    [GtkCallback]
    private void on_mandatory_input_changed () {
        notify_property ("ready-to-create");
    }

    [GtkCallback]
    private void on_username_entry_activated () {
        if (ready_for_express)
            user_wants_to_create ();
        else if (username != "" && product_key_format != null)
            product_key_entry.grab_focus (); // If username is provided, must be product key thats still not provided
    }

    [GtkCallback]
    private void on_password_button_clicked () {
        password_notebook.next_page ();
        password_entry.grab_focus ();
    }

    [GtkCallback]
    private bool on_password_entry_focus_out () {
        if (password_entry.text_length == 0)
            password_notebook.prev_page ();
        return false;
    }

    [GtkCallback]
    private void on_password_entry_activated () {
        if (ready_for_express)
            user_wants_to_create ();
        else if (username == "")
            username_entry.grab_focus ();
        else if (product_key_format != null)
            product_key_entry.grab_focus ();
    }

    [GtkCallback]
    private void on_key_entry_activated () {
        if (ready_for_express)
            user_wants_to_create ();
        else if (product_key_entry.text_length == product_key_format.length)
            username_entry.grab_focus (); // If product key is provided, must be username thats still not provided.
    }

    private bool we_inserted_text;

    [GtkCallback]
    private void on_key_text_inserted (string text, int text_length, ref int position) {
        if (we_inserted_text)
            return;

        var result = "";

        for (uint i = 0, j = position; i < text_length && j < product_key_format.length; ) {
            var character = text.get (i);
            var allowed_char = product_key_format.get (j);

            var skip_input_char = false;
            switch (allowed_char) {
            case '@': // Any character
                break;

            case '%': // Alphabet
                if (!character.isalpha ())
                    skip_input_char = true;
                break;

            case '#': // Numeric
                if (!character.isdigit ())
                    skip_input_char = true;
                break;

            case '$': // Alphnumeric
                if (!character.isalnum ())
                    skip_input_char = true;
                break;

            default: // Hardcoded character required
                if (character != allowed_char) {
                    result += allowed_char.to_string ();
                    j++;

                    continue;
                }

                break;
            }

            i++;
            if (skip_input_char)
                continue;

            result += character.to_string ();
            j++;
        }

        if (result != "") {
            we_inserted_text = true;
            product_key_entry.insert_text (result.up (), result.length, ref position);
            we_inserted_text = false;
        }

        Signal.stop_emission_by_name (product_key_entry, "insert-text");
    }
}

