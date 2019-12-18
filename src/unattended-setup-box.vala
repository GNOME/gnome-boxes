// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/unattended-setup-box.ui")]
private class Boxes.UnattendedSetupBox : Gtk.Box {
    private const string KEY_FILE = "setup-data.conf";
    private const string EXPRESS_KEY = "express-install";
    private const string USERNAME_KEY = "username";
    private const string PASSWORD_KEY = "password";
    private const string PRODUCTKEY_KEY = "product-key";

    public bool ready_for_express {
        get {
            return username != "" &&
                   !needs_password &&
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
                user_avatar.pixbuf = round_image (pixbuf);
            } catch (GLib.Error error) {
                debug ("Failed to load user avatar file '%s': %s", value, error.message);
            }
        }
    }

    public signal void user_wants_to_create (); // User wants to already create the VM

    private bool _needs_password;
    private bool needs_password {
        get {
            if (password != "")
                return false;

            return _needs_password;
        }

        set {
            _needs_password = value;
        }
    }

    [GtkChild]
    private Gtk.InfoBar needs_internet_bar;
    [GtkChild]
    private Gtk.Label needs_internet_label;
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
    private string media_path;
    private Cancellable cancellable = new Cancellable ();
    private GLib.KeyFile keyfile;
    private Secret.Schema secret_password_schema
            = new Secret.Schema ("org.gnome.Boxes",
                                 Secret.SchemaFlags.NONE,
                                 "gnome-boxes-media-path", Secret.SchemaAttributeType.STRING);

    public UnattendedSetupBox (InstallerMedia media, string? product_key_format, bool needs_internet) {
        this.product_key_format = product_key_format;

        var msg = _("Express installation of %s requires an internet connection.").printf (media.label);
        needs_internet_label.label = msg;
        needs_internet_bar.visible = needs_internet;
        needs_password = (media as UnattendedInstaller).needs_password;
        media_path = media.device_file;
        keyfile = new GLib.KeyFile ();

        try {
            var filename = get_user_unattended (KEY_FILE);
            keyfile.load_from_file (filename, KeyFileFlags.KEEP_COMMENTS);

            set_entry_text_from_key (username_entry, USERNAME_KEY, Environment.get_user_name ());
            set_entry_text_from_key (password_entry, PASSWORD_KEY);
            set_entry_text_from_key (product_key_entry, PRODUCTKEY_KEY);

            if (password != "") {
                password_notebook.next_page ();
            } else {
                Secret.password_lookup.begin (secret_password_schema, cancellable, (obj, res) => {
                    try {
                        var credentials_str = Secret.password_lookup.end (res);
                        if (credentials_str == null || credentials_str == "")
                            return;

                        try {
                            var credentials_variant = GLib.Variant.parse (null, credentials_str, null, null);
                            string password_str;
                            if (!credentials_variant.lookup ("password", "s", out password_str))
                                throw new Boxes.Error.INVALID ("couldn't unpack a string for the 'password' key");

                            if (password_str != null && password_str != "") {
                                password_entry.text = password_str;
                                password_notebook.next_page ();
                            }
                        } catch (GLib.Error error) {
                            warning ("Failed to parse password from the keyring: %s", error.message);
                        }
                    } catch (GLib.IOError.CANCELLED error) {
                        return;
                    } catch (GLib.Error error) {
                        warning ("Failed to lookup password for '%s' from the keyring: %s",
                                 media_path,
                                 error.message);
                    }
                }, "gnome-boxes-media-path", media_path);
            }

            try {
                keyfile.remove_key (media_path, PASSWORD_KEY);
            } catch (GLib.Error error) {
                debug ("Failed to remove key '%s' under '%s': %s", PASSWORD_KEY, media_path, error.message);
            }
        } catch (GLib.Error error) {
            debug ("%s either doesn't already exist or we failed to load it: %s", KEY_FILE, error.message);
        }
        setup_express_toggle (media.os_media.live, needs_internet);

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

    public override void dispose () {
        if (cancellable != null) {
            cancellable.cancel ();
            cancellable = null;
        }

        base.dispose ();
    }

    public void clean_up () {
        NetworkMonitor.get_default ().network_changed.disconnect (update_express_toggle);
    }

    public void save_settings () {
        keyfile.set_boolean (media_path, EXPRESS_KEY, express_install);
        keyfile.set_string (media_path, USERNAME_KEY, username);
        keyfile.set_string (media_path, PRODUCTKEY_KEY, product_key);

        var filename = get_user_unattended (KEY_FILE);
        try {
            keyfile.save_to_file (filename);
        } catch (GLib.Error error) {
            debug ("Error saving settings for '%s': %s", media_path, error.message);
        }

        if (password != null && password != "") {
            var variant_builder = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
            var password_variant = new GLib.Variant ("s", password);
            variant_builder.add ("{sv}", "password", password_variant);

            var credentials_variant = variant_builder.end ();
            var credentials_str = credentials_variant.print (true);

            var label = _("GNOME Boxes credentials for “%s”").printf (media_path);
            Secret.password_store.begin (secret_password_schema,
                                         Secret.COLLECTION_DEFAULT,
                                         label,
                                         credentials_str,
                                         null,
                                         (obj, res) => {
                try {
                    Secret.password_store.end (res);
                } catch (GLib.Error error) {
                    warning ("Failed to store password for '%s' in the keyring: %s", media_path, error.message);
                }
            }, "gnome-boxes-media-path", media_path);
        }
    }

    private void setup_express_toggle (bool live, bool needs_internet) {
        try {
            express_toggle.active = keyfile.get_boolean (media_path, EXPRESS_KEY);
        } catch (GLib.Error error) {
            debug ("Failed to read key '%s' under '%s': %s\n", EXPRESS_KEY, media_path, error.message);
            express_toggle.active = !live;
        }

        if (!needs_internet)
            return;

        var network_monitor = NetworkMonitor.get_default ();
        update_express_toggle (network_monitor.get_network_available ());
        network_monitor.network_changed.connect (update_express_toggle);
    }

    private void update_express_toggle(bool network_available) {
        if (network_available) {
            express_toggle.sensitive = true;
        } else {
            express_toggle.sensitive = false;
            express_toggle.active = false;
        }
    }

    private void set_entry_text_from_key (Gtk.Entry entry, string key, string? default_value = null) {
        string? str = null;
        try {
            str = keyfile.get_string (media_path, key);
        } catch (GLib.Error error) {
            debug ("Failed to read key '%s' under '%s': %s\n", key, media_path, error.message);
        }

        if (str != null && str != "")
            entry.text = str;
        else if (default_value != null)
            entry.text = default_value;
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
    private void on_password_entry_changed () {
        cancellable.cancel ();
        cancellable = new Cancellable ();
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

    [GtkCallback]
    private void on_secondary_icon_clicked () {
        password_entry.visibility = !password_entry.visibility;

        password_entry.secondary_icon_name = password_entry.visibility ?
                                             "eye-open-negative-filled-symbolic" :
                                             "eye-not-looking-symbolic";
    }
}

