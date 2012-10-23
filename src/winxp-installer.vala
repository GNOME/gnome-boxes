// This file is part of GNOME Boxes. License: LGPLv2+

using GVirConfig;

// Automated installer media for Windows XP, 2000 and 2003
private class Boxes.WinXPInstaller: WindowsInstaller {
    private const uint[] allowed_dash_positions = { 5, 11, 17, 23 };

    private static Regex key_regex;
    private static Regex admin_pass_regex;

    private Gtk.Entry key_entry;

    private ulong key_inserted_id; // ID of key_entry.insert_text signal handler

    public override bool ready_for_express {
        get {
            return base.ready_for_express && key_entry.text_length == 29;
        }
    }

    private bool has_viostor_drivers;

    public override bool supports_virtio_disk {
        get {
            return has_viostor_drivers;
        }
    }

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
        extra_iso = "win-tools.iso";
    }

    public override async void prepare_for_installation (string vm_name, Cancellable? cancellable) throws GLib.Error {
        bool have_viostor = false;
        has_viostor_drivers = false;

        yield base.prepare_for_installation (vm_name, cancellable);

        if (extra_iso == null)
            return;

        try {
            ISOExtractor extractor = new ISOExtractor (extra_iso);

            yield extractor.mount_media (cancellable);

            string driver_path = (os_media.architecture == "x86_64")? "preinst/winxp/amd64" : "preinst/winxp/x86";

            GLib.FileEnumerator enumerator = yield extractor.enumerate_children (driver_path, cancellable);
            GLib.List<FileInfo> infos = yield enumerator.next_files_async (4, GLib.Priority.DEFAULT, cancellable);
            while (infos != null) {
                foreach (var info in infos) {
                    string relative_path = Path.build_filename (driver_path, info.get_name ());
                    string full_path = extractor.get_absolute_path (relative_path);
                    var unattended_file = new UnattendedRawFile (this, full_path, info.get_name ());
                    debug ("Copying %s from extra ISO to unattended floppy", relative_path);
                    yield unattended_file.copy (cancellable);
                    if (info.get_name () == "viostor.sys")
                        have_viostor = true;
                }
                infos = yield enumerator.next_files_async (4, GLib.Priority.DEFAULT, cancellable);
            }

            // If we arrived there with no exception, then everything is setup for
            // the Windows installer to be able to use a virtio disk controller
            has_viostor_drivers = have_viostor;
        } catch (GLib.Error e) {
            has_viostor_drivers = false;
        }
    }

    protected override void setup_ui () {
        base.setup_ui ();

        // Microsoft Windows product key
        var label = new Gtk.Label (_("Product Key"));
        label.margin_top = 15;
        label.margin_right = 10;
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.CENTER;
        setup_grid.attach (label, 0, setup_grid_n_rows, 2, 1);
        express_toggle.bind_property ("active", label, "sensitive", 0);

        key_entry = create_input_entry ("");
        key_entry.width_chars = 29;
        key_entry.max_length = 29;
        key_entry.margin_top = 15;
        key_entry.halign = Gtk.Align.FILL;
        key_entry.valign = Gtk.Align.CENTER;
        key_entry.get_style_context ().add_class ("boxes-product-key-entry");
        setup_grid.attach (key_entry, 2, setup_grid_n_rows, 1, 1);
        express_toggle.bind_property ("active", key_entry, "sensitive", 0);
        setup_grid_n_rows++;

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
