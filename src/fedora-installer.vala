// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.FedoraInstaller: UnattendedInstaller {
    private bool mounted;

    private File source_dir;
    private File kernel_file;
    private File initrd_file;

    private string kernel_path;
    private string initrd_path;

    private string kbd;

    // F16 ships buggly QXL package and spice-vdagent package won't be shipped until F17 so we install from
    // up2date remote repos for anything less than F17.
    private bool use_remote_repos { get { return express_install && uint64.parse (os.version) < 17; } }

    private static Regex repo_regex;
    private static Regex kbd_regex;

    static construct {
        try {
            repo_regex = new Regex ("BOXES_FEDORA_REPOS");
            kbd_regex = new Regex ("BOXES_FEDORA_KBD");
        } catch (RegexError error) {
            // This just can't fail
            assert_not_reached ();
        }
    }

    public FedoraInstaller.from_media (InstallerMedia media) throws GLib.Error {
        var source_path = get_unattended ("fedora.ks");

        base.from_media (media, source_path, "ks.cfg");
        password_mandatory = true;

        kbd = fetch_console_kbd_layout ();
    }

    public override void set_direct_boot_params (GVirConfig.DomainOs os) {
        if (kernel_path == null || initrd_path == null)
            return;

        os.set_kernel (kernel_path);
        os.set_ramdisk (initrd_path);
        os.set_cmdline ("ks=hd:sda:/ks.cfg");
    }

    public override void check_needed_info () throws UnattendedInstallerError.SETUP_INCOMPLETE {
        base.check_needed_info ();

        if (!use_remote_repos)
            return;

        try {
            var client = new SocketClient ();
            client.connect_to_host ("fedoraproject.org", 80);
        } catch (GLib.Error error) {
            var message = _("Internet access required for express installation of Fedora 16 and older");

            throw new UnattendedInstallerError.SETUP_INCOMPLETE (message);
        }
    }

    protected override async void prepare_direct_boot (Cancellable? cancellable) throws GLib.Error {
        if (!express_toggle.active)
            return;

        if (os_media.kernel_path == null || os_media.initrd_path == null)
            return;

        yield mount_media (cancellable);

        yield extract_boot_files (cancellable);

        yield normal_clean_up (cancellable);
    }

    protected override void clean_up () throws GLib.Error {
        base.clean_up ();

        if (kernel_file != null) {
            delete_file (kernel_file);
            kernel_file = null;
        }

        if (initrd_file != null) {
            delete_file (initrd_file);
            initrd_file = null;
        }
    }

    protected override string fill_unattended_data (string data) throws RegexError {
        var str = base.fill_unattended_data (data);

        str = kbd_regex.replace (str, str.length, 0, kbd);

        var repos = (use_remote_repos) ? "repo --name=fedora\nrepo --name=updates" : "";

        return repo_regex.replace (str, str.length, 0, repos);
    }

    private async void normal_clean_up (Cancellable? cancellable) throws GLib.Error {
        if (!mounted)
            return;

        debug ("Unmounting '%s'..", mount_point);
        string[] argv = { "fusermount", "-u", mount_point };
        yield exec (argv, cancellable);
        mounted = false;
        debug ("Unmounted '%s'.", mount_point);

        source_dir.delete ();
        debug ("Removed '%s'.", mount_point);
        mount_point = null;
    }

    private async void mount_media (Cancellable? cancellable) throws GLib.Error {
        if (mount_point != null) {
            source_dir = File.new_for_path (mount_point);

            return;
        }

        mount_point = get_user_unattended ();
        var dir = File.new_for_path (mount_point);
        try {
            dir.make_directory (null);
        } catch (IOError.EXISTS error) {}
        source_dir = dir;

        debug ("Mounting '%s' on '%s'..", device_file, mount_point);
        string[] argv = { "fuseiso", device_file, mount_point };
        yield exec (argv, cancellable);
        debug ("'%s' now mounted on '%s'.", device_file, mount_point);

        mounted = true;
    }

    private async void extract_boot_files (Cancellable? cancellable) throws GLib.Error {
        kernel_path = Path.build_filename (mount_point, os_media.kernel_path);
        kernel_file = File.new_for_path (kernel_path);
        initrd_path = Path.build_filename (mount_point, os_media.initrd_path);
        initrd_file = File.new_for_path (initrd_path);

        if (!mounted)
            return;

        kernel_path = get_user_unattended ("kernel");
        kernel_file = yield copy_file (kernel_file, kernel_path, cancellable);
        initrd_path = get_user_unattended ("initrd");
        initrd_file = yield copy_file (initrd_file, initrd_path, cancellable);
    }

    private async File copy_file (File file, string dest_path, Cancellable? cancellable) throws GLib.Error {
        var dest_file = File.new_for_path (dest_path);

        try {
            debug ("Copying '%s' to '%s'..", file.get_path (), dest_path);
            yield file.copy_async (dest_file, 0, Priority.DEFAULT, cancellable);
            debug ("Copied '%s' to '%s'.", file.get_path (), dest_path);
        } catch (IOError.EXISTS error) {}

        return dest_file;
    }

    private struct KbdLayout {
        public string xkb_layout;
        public string xkb_variant;
        public string console_layout;
    }

    private string fetch_console_kbd_layout () {
        var settings = new GLib.Settings ("org.gnome.libgnomekbd.keyboard");
        var layouts = settings.get_strv ("layouts");
        var layout_str = layouts[0];
        if (layout_str == null || layout_str == "") {
            warning ("Failed to fetch prefered keyboard layout from user settings, falling back to 'us'..");

            return "us";
        }

        var tokens = layout_str.split("\t");
        var xkb_layout = tokens[0];
        var xkb_variant = tokens[1];
        var console_layout = (string) null;

        for (var i = 0; i < kbd_layouts.length; i++)
            if (xkb_layout == kbd_layouts[i].xkb_layout)
                if (xkb_variant == kbd_layouts[i].xkb_variant) {
                    console_layout = kbd_layouts[i].console_layout;

                    // Exact match found already, no need to iterate anymore..
                    break;
                } else if (kbd_layouts[i].xkb_variant == null)
                    console_layout = kbd_layouts[i].console_layout;

        if (console_layout == null) {
            debug ("Couldn't find a console layout for X layout '%s', falling back to 'us'..", layout_str);
            console_layout = "us";
        }
        debug ("Using '%s' keyboard layout.", console_layout);

        return console_layout;
    }

    // Modified copy of KeyboardModels._modelDict from system-config-keyboard project:
    // https://fedorahosted.org/system-config-keyboard/
    //
    private const KbdLayout[] kbd_layouts = {
        { "ara", null, "ar-azerty" },
        { "ara", "azerty", "ar-azerty" },
        { "ara", "azerty_digits", "ar-azerty-digits" },
        { "ara", "digits", "ar-digits" },
        { "ara", "qwerty", "ar-qwerty" },
        { "ara", "qwerty_digits", "ar-qwerty-digits" },
        { "be", null, "be-latin1" },
        { "bg", null, "bg_bds-utf8" },
        { "bg", "phonetic", "bg_pho-utf8" },
        { "bg", "bas_phonetic", "bg_pho-utf8" },
        { "br", null, "br-abnt2" },
        { "ca(fr)", null, "cf" },
        { "hr", null, "croat" },
        { "cz", null, "cz-us-qwertz" },
        { "cz", "qwerty", "cz-lat2" },
        { "cz", "", "cz-us-qwertz" },
        { "de", null, "de" },
        { "de", "nodeadkeys", "de-latin1-nodeadkeys" },
        { "dev", null, "dev" },
        { "dk", null, "dk" },
        { "dk", "dvorak", "dk-dvorak" },
        { "es", null, "es" },
        { "ee", null, "et" },
        { "fi", null, "fi" },
        { "fr", null, "fr" },
        { "fr", "latin9", "fr-latin9" },
        { "gr", null, "gr" },
        { "gur", null, "gur" },
        { "hu", null, "hu" },
        { "hu", "qwerty", "hu101" },
        { "ie", null, "ie" },
        { "in", null, "us" },
        { "in", "ben", "ben" },
        { "in", "ben-probhat", "ben_probhat" },
        { "in", "guj", "guj" },
        { "in", "tam", "tml-inscript" },
        { "in", "tam_TAB", "tml-uni" },
        { "is", null, "is-latin1" },
        { "it", null, "it" },
        { "jp", null, "jp106" },
        { "kr", null, "ko" },
        { "latam", null, "la-latin1" },
        { "mkd", null, "mk-utf" },
        { "nl", null, "nl" },
        { "no", null, "no" },
        { "pl", null, "pl2" },
        { "pt", null, "pt-latin1" },
        { "ro", null, "ro" },
        { "ro", "std", "ro-std" },
        { "ro", "cedilla", "ro-cedilla" },
        { "ro", "std_cedilla", "ro-std-cedilla" },
        { "ru", null, "ru" },
        { "rs", null, "sr-cy" },
        { "rs", "latin", "sr-latin"},
        { "se", null, "sv-latin1" },
        { "ch", "de_nodeadkeys", "sg" },
        { "ch", "fr", "fr_CH" },
        { "sk", null, "sk-qwerty" },
        { "si", null, "slovene" },
        { "tj", null, "tj" },
        { "tr", null, "trq" },
        { "gb", null, "uk" },
        { "ua", null, "ua-utf" },
        { "us", null, "us" },
        { "us", "intl", "us-acentos" }
    };
}
