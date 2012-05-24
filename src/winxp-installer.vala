// This file is part of GNOME Boxes. License: LGPLv2+

// Automated installer media for Windows XP, 2000 and 2003
private class Boxes.WinXPInstaller: WindowsInstaller {
    private const uint[] allowed_dash_positions = { 5, 11, 17, 23 };

    private static Regex key_regex;
    private static Regex admin_pass_regex;

    private Gtk.Entry key_entry;

    private ulong key_inserted_id; // ID of key_entry.insert_text signal handler

    static construct {
        try {
            key_regex = new Regex ("BOXES_PRODUCT_KEY");
            admin_pass_regex = new Regex ("BOXES_XP_ADMIN_PASSWORD");
        } catch (RegexError error) {
            // This just can't fail
            assert_not_reached ();
        }
    }

    public WinXPInstaller.from_media (InstallerMedia media) throws GLib.Error {
        var unattended_source = get_unattended (media.os.short_id + ".sif");
        var avatar_format = new AvatarFormat ("bmp", ".bmp", false, 48, 48);
        base.from_media (media, unattended_source, "Winnt.sif", avatar_format);

        var name = media.os.short_id + ".cmd";
        unattended_source = get_unattended (name);
        add_unattended_file (new UnattendedTextFile (this, unattended_source, name));

        name = media.os.short_id + ".reg";
        unattended_source = get_unattended (name);
        add_unattended_file (new UnattendedTextFile (this, unattended_source, name));
        newline_type = DataStreamNewlineType.CR_LF;
    }

    protected override void setup_ui () {
        base.setup_ui ();

        setup_table.resize (setup_table.n_rows + 1, setup_table.n_columns);

        var hbox = new Gtk.HBox (false, 10);
        hbox.margin_top = 12;

        // Microsoft Windows product key
        var label = new Gtk.Label (_("Product Key"));
        label.halign = Gtk.Align.START;
        hbox.pack_start (label, true, true, 0);

        var notebook = new Gtk.Notebook ();
        notebook.show_tabs = false;
        notebook.show_border = false;
        var button = new Gtk.Button.with_mnemonic (_("_Add Product Key"));
        notebook.append_page (button);
        key_entry = new Gtk.Entry ();
        key_entry.width_chars = 29;
        key_entry.max_length = 29;
        key_entry.get_style_context ().add_class ("boxes-product-key-entry");
        notebook.append_page (key_entry);

        button.clicked.connect (() => {
            notebook.next_page ();
            key_entry.is_focus = true;
        });

        hbox.pack_start (notebook, true, true, 0);
        setup_table.attach_defaults (hbox, 0, setup_table.n_columns, setup_table.n_rows - 1, setup_table.n_rows);

        express_toggle.bind_property ("active", hbox, "sensitive", 0);

        key_inserted_id = key_entry.insert_text.connect (on_key_text_inserted);
    }

    protected override string fill_unattended_data (string data) throws RegexError {
        var str = base.fill_unattended_data (data);
        var admin_pass = (password != "") ? password : "*";
        str = admin_pass_regex.replace (str, str.length, 0, admin_pass);

        return key_regex.replace (str, str.length, 0, key_entry.text);
    }

    private void on_key_text_inserted (string text, int text_length, ref int position) {
        var result = "";

        uint i = 0;
        foreach (var character  in ((char[]) text.data)) {
            var char_position = i + position;

            if (character != '-') {
                if (!character.isalnum ())
                    continue;

                if (char_position in allowed_dash_positions) {
                    // Insert dash in the right place for our dear user
                    result += "-";
                    i++;
                }
            } else if (!(char_position in allowed_dash_positions))
                continue;

            result += character.to_string ();
            i++;
        }

        if (result != "") {
            SignalHandler.block (key_entry, key_inserted_id);
            key_entry.insert_text (result.up (), result.length, ref position);
            SignalHandler.unblock (key_entry, key_inserted_id);
        }

        Signal.stop_emission_by_name (key_entry, "insert-text");
    }
}
