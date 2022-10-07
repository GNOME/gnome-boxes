// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/unattended-setup-box.ui")]
private class Boxes.UnattendedSetupBox : Gtk.Box {
    public bool ready_for_express {
        get {
            return username != "" &&
                   !needs_password;
        }
    }

    public bool ready_to_create {
        get {
            return !express_install || ready_for_express;
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
    private unowned Gtk.InfoBar needs_internet_bar;
    [GtkChild]
    private unowned Gtk.Label needs_internet_label;
    [GtkChild]
    public unowned Gtk.Switch express_toggle;
    [GtkChild]
    private unowned Hdy.ActionRow username_row;
    [GtkChild]
    private unowned Gtk.Entry username_entry;
    [GtkChild]
    private unowned Hdy.ActionRow password_row;
    [GtkChild]
    private unowned Gtk.Entry password_entry;
    [GtkChild]
    private unowned Hdy.ActionRow product_key_row;
    [GtkChild]
    private unowned Gtk.Entry product_key_entry;

    private string? product_key_format;
    private string media_path;
    private Cancellable cancellable = new Cancellable ();
    private Secret.Schema secret_password_schema
            = new Secret.Schema ("org.gnome.Boxes",
                                 Secret.SchemaFlags.NONE,
                                 "gnome-boxes-media-path", Secret.SchemaAttributeType.STRING);

    public UnattendedSetupBox (InstallerMedia media, string? product_key_format, bool needs_internet) {
        this.product_key_format = product_key_format;

        var msg = _("Express installation of %s requires an internet connection.").printf (media.label);
        needs_internet_label.label = msg;
        needs_internet_bar.visible = needs_internet;

        var unnatended_installer = media as UnattendedInstaller;
        needs_password = unnatended_installer.needs_password;

        media_path = media.device_file;

        express_install = !media.os_media.live;

        if (product_key_format != null) {
            product_key_row.visible = true;

            product_key_entry.width_chars = product_key_format.length;
            product_key_entry.max_length = product_key_format.length;
        }

        load_credentials ();
    }

    public async void load_credentials () {
        Secret.password_lookup (secret_password_schema, cancellable, (obj, res) => {
            try {
                var credentials_str = Secret.password_lookup.end (res);
                if (credentials_str == null || credentials_str == "")
                    return;

                try {
                    var credentials_variant = GLib.Variant.parse (null, credentials_str, null, null);
                    var credentials = new GLib.VariantDict (credentials_variant);

                    string username_str;
                    string password_str;
                    string product_key_str;

                    if (credentials.lookup ("username", "s", out username_str)) {
                        username_entry.text = username_str;
                        debug ("Username '%s' found in the keyring", username_str);
                    }
                    if (credentials.lookup ("password", "s", out password_str)) {
                        password_entry.text = password_str;
                        debug ("Password '%s' found in the keyring", password_str);
                    }
                    if (credentials.lookup ("product-key", "s", out product_key_str)) {
                        product_key_entry.text = product_key_str;
                        debug ("Product-key found '%s' found in the keyring", product_key_str);
                    }

                } catch (GLib.Error error) {
                    debug ("Failed to parse credentials from the keyring: %s", error.message);
                }
            } catch (GLib.IOError.CANCELLED error) {
                return;
            } catch (GLib.Error error) {
                debug ("Failed to lookup credentials for '%s' from the keyring: %s",
                       media_path,
                       error.message);
            }
        }, "gnome-boxes-media-path", media_path);
    }

    public override void dispose () {
        if (cancellable != null) {
            cancellable.cancel ();
            cancellable = null;
        }

        base.dispose ();
    }

    public void clean_up () {
    }

    public async void save_credentials () {
        var variant_builder = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
        variant_builder.add ("{sv}", "username", new GLib.Variant ("s", username));
        variant_builder.add ("{sv}", "password", new GLib.Variant ("s", password));
        variant_builder.add ("{sv}", "product-key", new GLib.Variant ("s", product_key));

        var credentials_variant = variant_builder.end ();
        var credentials_str = credentials_variant.print (true);

        var label = _("GNOME Boxes credentials for “%s”").printf (media_path);
        Secret.password_store (secret_password_schema,
                               Secret.COLLECTION_DEFAULT,
                               label,
                               credentials_str,
                               null,
                               (obj, res) => {
            try {
                Secret.password_store.end (res);
            } catch (GLib.Error error) {
                debug ("Failed to store credentials for '%s' in the keyring: %s", media_path, error.message);
            }
        }, "gnome-boxes-media-path", media_path);
    }

    [GtkCallback]
    private void on_mandatory_input_changed () {
        notify_property ("ready-to-create");

        username_row.sensitive = express_install;
        password_row.sensitive = express_install;
        product_key_row.sensitive = express_install;
    }

    [GtkCallback]
    private void on_username_entry_activated () {
        if (ready_for_express)
            user_wants_to_create ();
        else if (username != "" && product_key_format != null)
            product_key_entry.grab_focus (); // If username is provided, must be product key thats still not provided
    }

    [GtkCallback]
    private void on_password_entry_changed () {
        cancellable.cancel ();
        cancellable = new Cancellable ();
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

