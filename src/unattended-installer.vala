// This file is part of GNOME Boxes. License: LGPLv2+

using GVirConfig;
using Osinfo;

private class Boxes.UnattendedInstaller: InstallerMedia {
    public override bool need_user_input_for_vm_creation {
        get {
            return !live; // No setup required by live media (and unknown medias are not UnattendedInstaller instances)
        }
    }

    public bool ready_for_express {
        get {
            return username != "" &&
                   (product_key_format == null ||
                    key_entry.text_length == product_key_format.length);
        }
    }

    public override bool ready_to_create {
        get {
            return !express_toggle.active || ready_for_express;
        }
    }

    public override bool supports_virtio_disk {
        get {
            return base.supports_virtio_disk || has_viostor_drivers;
        }
    }

    public bool express_install {
        get { return express_toggle.active; }
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

    public File? disk_file;
    public File? kernel_file;
    public File? initrd_file;
    public InstallConfig config;
    public InstallScriptList scripts;

    private bool has_viostor_drivers;
    private string? product_key_format;

    private GLib.List<UnattendedFile> unattended_files;
    private UnattendedAvatarFile avatar_file;

    private Gtk.Grid setup_grid;
    private int setup_grid_n_rows;

    private Gtk.Label setup_label;
    private Gtk.HBox setup_hbox;
    private Gtk.Switch express_toggle;
    private Gtk.Entry username_entry;
    private Gtk.Entry password_entry;
    private Gtk.Entry key_entry;

    private string timezone;
    private string lang;
    private string hostname;
    private string kbd;

    ulong key_inserted_id; // ID of key_entry.insert_text signal handler

    private static Fdo.Accounts? accounts;

    construct {
        /* We can't do this in the class constructor as the sync call can
           cause deadlocks, see bug #676679. */
        if (accounts == null) {
            try {
                accounts = Bus.get_proxy_sync (BusType.SYSTEM, "org.freedesktop.Accounts", "/org/freedesktop/Accounts");
            } catch (GLib.Error error) {
                warning ("Failed to connect to D-Bus service '%s': %s", "org.freedesktop.Accounts", error.message);
            }
        }
    }

    private string get_preferred_language () {
        var system_langs = Intl.get_language_names ();
        var media_langs = new HashTable<string, unowned string> (str_hash, str_equal);
        var media_langs_list = os_media.languages;

        foreach (var lang in media_langs_list)
            media_langs.add (lang);

        foreach (var lang in system_langs) {
            if (lang in media_langs) {
                debug ("matched %s", lang);
                return lang;
            }
        }

        if (media_langs_list != null) {
            debug ("Failed to match system locales with media languages, falling back to %s media language", media_langs_list.nth_data (0));
            return media_langs_list.nth_data (0);
        }

        debug ("No media language, using %s locale", system_langs[0]);

        return system_langs[0];
    }

    public async UnattendedInstaller.from_media (InstallerMedia media, InstallScriptList scripts) throws GLib.Error {
        os = media.os;
        os_media = media.os_media;
        label = media.label;
        device_file = media.device_file;
        from_image = media.from_image;
        mount_point = media.mount_point;
        resources = media.resources;

        this.scripts = scripts;
        config = new InstallConfig ("http://live.gnome.org/Boxes/unattended");

        unattended_files = new GLib.List<UnattendedFile> ();
        foreach (var s in scripts.get_elements ()) {
            var script = s as InstallScript;
            var filename = script.get_expected_filename ();
            add_unattended_file (new UnattendedTextFile (this, script, filename));
        }

        var time = TimeVal ();
        var date = new DateTime.from_timeval_local (time);
        timezone = date.get_timezone_abbreviation ();

        lang = get_preferred_language ();
        kbd = lang;
        product_key_format = get_product_key_format ();

        setup_ui ();

        yield setup_pre_install_drivers ();
    }

    public override async void prepare_for_installation (string vm_name, Cancellable? cancellable) throws GLib.Error {
        if (!express_toggle.active) {
            debug ("Unattended installation disabled.");

            return;
        }
        this.hostname = vm_name.replace (" ", "-");

        try {
            yield create_disk_image (cancellable);

            foreach (var unattended_file in unattended_files)
                yield unattended_file.copy (cancellable);

            //FIXME: Linux-specific. Any generic way to achieve this?
            if (os_media.kernel_path != null && os_media.initrd_path != null) {
                var extractor = new ISOExtractor (device_file);

                yield extractor.mount_media (cancellable);

                yield extract_boot_files (extractor, cancellable);
            }
        } catch (GLib.Error error) {
            clean_up ();
            // An error occurred when trying to setup unattended installation, but it's likely that a non-unattended
            // installation will work. When this happens, just disable unattended installs, and let the caller decide
            // if it wants to retry a non-automatic install or to just abort the box creation..
            express_toggle.active = false;

            throw error;
        } finally {
            unattended_files = null;
        }
    }

    public override void setup_domain_config (Domain domain) {
        base.setup_domain_config (domain);

        var disk = get_unattended_disk_config ();
        if (disk != null)
            domain.add_device (disk);
    }

    public void configure_install_script (InstallScript script) {
        if (password != null) {
            config.set_user_password (password);
            config.set_admin_password (password);
        }
        if (username != null) {
            config.set_user_login (username);
            config.set_user_realname (username);
        }
        if (key_entry != null && key_entry.text != null)
            config.set_reg_product_key (key_entry.text);
        config.set_l10n_timezone (timezone);
        config.set_l10n_language (lang);
        config.set_l10n_keyboard (kbd);
        config.set_hostname (hostname);
        config.set_hardware_arch (os_media.architecture);

        // FIXME: Ideally, we shouldn't need to check for distro
        if (os.distro == "win")
            config.set_target_disk ("C");
        else
            config.set_target_disk (supports_virtio_disk? "/dev/vda" : "/dev/sda");

        string device_name;
        get_unattended_disk_info (script.path_format, out device_name);
        config.set_script_disk (device_name_to_path (script.path_format, device_name));

        if (avatar_file != null) {
            var location = ((script.path_format == PathFormat.UNIX)? "/" : "\\") + avatar_file.dest_name;
            config.set_avatar_location (location);
            config.set_avatar_disk (config.get_script_disk ());
        }

        config.set_pre_install_drivers_disk (config.get_script_disk ());
    }

    public override void populate_setup_vbox (Gtk.VBox setup_vbox) {
        foreach (var child in setup_vbox.get_children ())
            setup_vbox.remove (child);

        setup_vbox.pack_start (setup_label, false, false);
        setup_vbox.pack_start (setup_hbox, false, false);
        setup_vbox.show_all ();
    }

    public override GLib.List<Pair> get_vm_properties () {
        var properties = base.get_vm_properties ();

        if (express_install) {
            properties.append (new Pair<string,string> (_("Username"), username));
            properties.append (new Pair<string,string> (_("Password"), hidden_password));
        }

        return properties;
    }

    public override void set_direct_boot_params (GVirConfig.DomainOs os) {
        if (kernel_file == null || initrd_file == null)
            return;

        // FIXME: This commandline should come from libosinfo somehow
        var script = scripts.get_nth (0) as InstallScript;
        var cmdline = "ks=hd:sda:/" + script.get_expected_filename ();

        os.set_kernel (kernel_file.get_path ());
        os.set_ramdisk (initrd_file.get_path ());
        os.set_cmdline (cmdline);
    }

    public string get_user_unattended (string? suffix = null) {
        var filename = hostname;
        if (suffix != null)
            filename += "-" + suffix;

        return get_user_pkgcache (filename);
    }

    private void setup_ui () {
        setup_label = new Gtk.Label (_("Choose express install to automatically preconfigure the box with optimal settings."));
        setup_label.wrap = true;
        setup_label.width_chars = 30;
        setup_label.halign = Gtk.Align.START;
        setup_hbox = new Gtk.HBox (false, 0);
        setup_hbox.valign = Gtk.Align.START;
        setup_hbox.margin = 24;

        setup_grid = new Gtk.Grid ();
        setup_hbox.pack_start (setup_grid, false, false);
        setup_grid.column_spacing = 0;
        setup_grid.column_homogeneous = false;
        setup_grid.row_spacing = 0;
        setup_grid.row_homogeneous = true;

        // First row
        // Translators: 'Express Install' means that the new box installation will be fully automated, the user
        // won't be asked anything while it's performed.
        var label = new Gtk.Label (_("Express Install"));
        label.margin_right = 10;
        label.margin_bottom = 15;
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.CENTER;
        setup_grid.attach (label, 0, 0, 2, 1);

        express_toggle = new Gtk.Switch ();
        express_toggle.active = !os_media.live;
        express_toggle.margin_bottom = 15;
        express_toggle.halign = Gtk.Align.START;
        express_toggle.valign = Gtk.Align.CENTER;
        express_toggle.notify["active"].connect (() => { notify_property ("ready-to-create"); });
        setup_grid.attach (express_toggle, 2, 0, 1, 1);
        setup_grid_n_rows++;

        // 2nd row (while user avatar spans over 2 rows)
        var avatar = new Gtk.Image.from_icon_name ("avatar-default", 0);
        avatar.pixel_size = 64;
        avatar.margin_right = 15;
        avatar.valign = Gtk.Align.CENTER;
        avatar.halign = Gtk.Align.CENTER;
        setup_grid.attach (avatar, 0, 1, 1, 2);
        avatar.show_all ();
        fetch_user_avatar.begin (avatar);

        label = new Gtk.Label (_("Username"));
        label.margin_right = 10;
        label.margin_bottom  = 10;
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.END;
        setup_grid.attach (label, 1, 1, 1, 1);
        username_entry = create_input_entry (Environment.get_user_name ());
        username_entry.margin_bottom  = 10;
        username_entry.halign = Gtk.Align.FILL;
        username_entry.valign = Gtk.Align.END;
        setup_grid.attach (username_entry, 2, 1, 1, 1);
        setup_grid_n_rows++;

        // 3rd row
        label = new Gtk.Label (_("Password"));
        label.margin_right = 10;
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.START;
        setup_grid.attach (label, 1, 2, 1, 1);

        var notebook = new Gtk.Notebook ();
        notebook.show_tabs = false;
        notebook.show_border = false;
        notebook.halign = Gtk.Align.FILL;
        notebook.valign = Gtk.Align.START;
        var button = new Gtk.Button.with_mnemonic (_("_Add Password"));
        button.visible = true;
        notebook.append_page (button);
        password_entry = create_input_entry ("", false, false);
        notebook.append_page (password_entry);
        button.clicked.connect (() => {
            notebook.next_page ();
            password_entry.is_focus = true;
        });
        password_entry.focus_out_event.connect (() => {
            if (password_entry.text_length == 0)
                notebook.prev_page ();
            return false;
        });
        setup_grid.attach (notebook, 2, 2, 1, 1);
        setup_grid_n_rows++;

        foreach (var child in setup_grid.get_children ())
            if (child != express_toggle)
                express_toggle.bind_property ("active", child, "sensitive", BindingFlags.SYNC_CREATE);

        if (product_key_format == null)
            return;

        label = new Gtk.Label (_("Product Key"));
        label.margin_top = 15;
        label.margin_right = 10;
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.CENTER;
        setup_grid.attach (label, 0, setup_grid_n_rows, 2, 1);
        express_toggle.bind_property ("active", label, "sensitive", 0);

        key_entry = create_input_entry ("");
        key_entry.width_chars = product_key_format.length;
        key_entry.max_length =  product_key_format.length;
        key_entry.margin_top = 15;
        key_entry.halign = Gtk.Align.FILL;
        key_entry.valign = Gtk.Align.CENTER;
        key_entry.get_style_context ().add_class ("boxes-product-key-entry");
        setup_grid.attach (key_entry, 2, setup_grid_n_rows, 1, 1);
        express_toggle.bind_property ("active", key_entry, "sensitive", 0);
        setup_grid_n_rows++;

        key_inserted_id = key_entry.insert_text.connect (on_key_text_inserted);
    }

    private void on_key_text_inserted (string text, int text_length, ref int position) {
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
            SignalHandler.block (key_entry, key_inserted_id);
            key_entry.insert_text (result.up (), result.length, ref position);
            SignalHandler.unblock (key_entry, key_inserted_id);
        }

        Signal.stop_emission_by_name (key_entry, "insert-text");
    }

    private void clean_up () throws GLib.Error {
        if (disk_file != null) {
            delete_file (disk_file);
            disk_file = null;
        }

        if (kernel_file != null) {
            delete_file (kernel_file);
            kernel_file = null;
        }

        if (initrd_file != null) {
            delete_file (initrd_file);
            initrd_file = null;
        }
    }

    private DomainDisk? get_unattended_disk_config () {
        if (!express_toggle.active)
            return null;

        return_val_if_fail (disk_file != null, null);

        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("raw");
        disk.set_source (disk_file.get_path ());

        string device_name;
        var device_type = get_unattended_disk_info (PathFormat.UNIX, out device_name);
        disk.set_guest_device_type (device_type);
        disk.set_target_dev (device_name);

        return disk;
    }

    private DomainDiskGuestDeviceType get_unattended_disk_info (PathFormat path_format, out string device_name) {
        // FIXME: Ideally, we shouldn't need to check for distro
        if (os.distro == "win") {
            device_name = (path_format == PathFormat.DOS)? "A" : "fd";

            return DomainDiskGuestDeviceType.FLOPPY;
        } else {
            // Path format checks below are most probably practically redundant but a small price for future safety
            if (supports_virtio_disk)
                device_name = (path_format == PathFormat.UNIX)? "sda" : "E";
            else
                device_name = (path_format == PathFormat.UNIX)? "sdb" : "E";

            return DomainDiskGuestDeviceType.DISK;
        }
    }

    private string device_name_to_path (PathFormat path_format, string name) {
        return (path_format == PathFormat.UNIX)? "/dev/" + name : name;
    }

    private void add_unattended_file (UnattendedFile file) {
        unattended_files.append (file);
    }

    private Gtk.Entry create_input_entry (string text, bool mandatory = true, bool visibility = true) {
        var entry = new Gtk.Entry ();
        entry.visibility = visibility;
        entry.visible = true;
        entry.text = text;

        if (mandatory)
            entry.notify["text"].connect (() => {
                notify_property ("ready-to-create");
            });

        return entry;
    }

    private async void create_disk_image (Cancellable? cancellable) throws GLib.Error {
        var disk_path = get_user_unattended ("unattended.img");
        disk_file = File.new_for_path (disk_path);

        var template_path = get_unattended ("disk.img");
        var template_file = File.new_for_path (template_path);

        debug ("Creating disk image for unattended installation at '%s'..", disk_path);
        yield template_file.copy_async (disk_file, FileCopyFlags.OVERWRITE, Priority.DEFAULT, cancellable);
        debug ("Floppy image for unattended installation created at '%s'", disk_path);
    }

    private async void fetch_user_avatar (Gtk.Image avatar) {
        if (accounts == null)
            return;

        var username = Environment.get_user_name ();
        string avatar_path = "/var/lib/AccountsService/icons/" + username;

        try {
            var path = yield accounts.FindUserByName (Environment.get_user_name ());
            Fdo.AccountsUser user = yield Bus.get_proxy (BusType.SYSTEM, "org.freedesktop.Accounts", path);
            avatar_path = user.IconFile;
        } catch (GLib.IOError error) {
            warning ("Failed to retrieve information about user '%s': %s", username, error.message);
        }

        try {
            var pixbuf = new Gdk.Pixbuf.from_file_at_scale (avatar_path, 64, 64, true);
            avatar.pixbuf = pixbuf;

            AvatarFormat avatar_format = null;
            foreach (var s in scripts.get_elements ()) {
                var script = s as InstallScript;
                avatar_format = script.avatar_format;
                if (avatar_format != null)
                    break;
            }

            avatar_file = new UnattendedAvatarFile (this, avatar_path, avatar_format);
            add_unattended_file (avatar_file);
        } catch (GLib.Error error) {
            debug ("Failed to load user avatar file '%s': %s", avatar_path, error.message);
        }
    }

    private async void extract_boot_files (ISOExtractor extractor, Cancellable cancellable) throws GLib.Error {
        string src_path = extractor.get_absolute_path (os_media.kernel_path);
        string dest_path = get_user_unattended ("kernel");
        kernel_file = yield copy_file (src_path, dest_path, cancellable);

        src_path = extractor.get_absolute_path (os_media.initrd_path);
        dest_path = get_user_unattended ("initrd");
        initrd_file = yield copy_file (src_path, dest_path, cancellable);
    }

    private async File copy_file (string src_path, string dest_path, Cancellable cancellable) throws GLib.Error {
        var src_file = File.new_for_path (src_path);
        var dest_file = File.new_for_path (dest_path);

        try {
            debug ("Copying '%s' to '%s'..", src_path, dest_path);
            yield src_file.copy_async (dest_file, 0, Priority.DEFAULT, cancellable);
            debug ("Copied '%s' to '%s'.", src_path, dest_path);
        } catch (IOError.EXISTS error) {}

        return dest_file;
    }

    private string? get_product_key_format () {
        // FIXME: We don't support the case of multiple scripts requiring different kind of product keys.
        foreach (var s in scripts.get_elements ()) {
            var script = s as InstallScript;

            var param = script.get_config_param (INSTALL_CONFIG_PROP_REG_PRODUCTKEY);
            if (param == null || param.is_optional ())
                continue;

            var format = script.get_product_key_format ();
            if (format != null)
                return format;
        }

        return null;
    }

    private async void setup_pre_install_drivers (Cancellable? cancellable = null) {
        foreach (var d in os.get_device_drivers ().get_elements ()) {
            var driver = d as DeviceDriver;
            if (driver.get_architecture () != os_media.architecture || !driver.get_pre_installable ())
                continue;

            foreach (var s in scripts.get_elements ()) {
                var script = s as InstallScript;
                if (!script.get_can_pre_install_drivers ())
                    continue;

                try {
                    yield setup_pre_install_driver_for_script (driver, script, cancellable);
                } catch (GLib.Error e) {
                    debug ("Failed to make use of drivers at '%s': %s", driver.get_location (), e.message);
                }
            }
        }
    }

    private async void setup_pre_install_driver_for_script (DeviceDriver driver,
                                                            InstallScript script,
                                                            Cancellable? cancellable) throws GLib.Error {
        var downloader = Downloader.get_instance ();

        var driver_files = new GLib.List<UnattendedFile> ();
        var location = driver.get_location ();
        var location_checksum = Checksum.compute_for_string (ChecksumType.MD5, location);
        foreach (var filename in driver.get_files ()) {
            var file_uri = location + "/" + filename;
            var file = File.new_for_uri (file_uri);

            var cached_path = get_drivers_cache (location_checksum + "-" + file.get_basename ());

            file = yield downloader.download (file, cached_path);

            driver_files.append (new UnattendedRawFile (this, cached_path, filename));
        }

        // We don't do this in above loop to ensure we have all the driver files
        foreach (var driver_file in driver_files)
            add_unattended_file (driver_file);

        foreach (var d in driver.get_devices ().get_elements ()) {
            var device = d as Device;

            if (device.get_name () == "virtio-block") {
                has_viostor_drivers = true;

                break;
            }
        }
    }
}

private interface Boxes.UnattendedFile : GLib.Object {
    public abstract string src_path { get; set; }
    public abstract string dest_name { get; set; }

    protected abstract UnattendedInstaller installer  { get; set; }

    public async void copy (Cancellable? cancellable) throws GLib.Error {
        var source_file = yield get_source_file (cancellable);

        debug ("Copying unattended file '%s' into disk drive/image '%s'", dest_name, installer.disk_file.get_path ());
        // FIXME: Perhaps we should use libarchive for this?
        string[] argv = { "mcopy", "-n", "-o", "-i", installer.disk_file.get_path (),
                                   source_file.get_path (),
                                   "::" + dest_name };
        yield exec (argv, cancellable);
        debug ("Copied unattended file '%s' into disk drive/image '%s'", dest_name, installer.disk_file.get_path ());
    }

    protected abstract async File get_source_file (Cancellable? cancellable)  throws GLib.Error;
}

private class Boxes.UnattendedRawFile : GLib.Object, Boxes.UnattendedFile {
    public string dest_name { get; set; }
    public string src_path { get; set; }

    protected UnattendedInstaller installer  { get; set; }

    public UnattendedRawFile (UnattendedInstaller installer, string src_path, string dest_name) {
       this.installer = installer;
       this.src_path = src_path;
       this.dest_name = dest_name;
    }

    protected async File get_source_file (Cancellable? cancellable)  throws GLib.Error {
        return File.new_for_path (src_path);
    }
}

private class Boxes.UnattendedTextFile : GLib.Object, Boxes.UnattendedFile {
    public string dest_name { get; set; }
    public string src_path { get; set; }

    protected UnattendedInstaller installer { get; set; }
    protected InstallScript script { get; set; }

    private File unattended_tmp;

    public UnattendedTextFile (UnattendedInstaller installer, InstallScript script, string dest_name) {
       this.installer = installer;
       this.script = script;
       this.dest_name = dest_name;
    }

    ~UnattendedTextFile () {
        if (unattended_tmp == null)
            return;

        try {
            delete_file (unattended_tmp);
        } catch (GLib.Error e) {
            warning ("Error deleting %s: %s", unattended_tmp.get_path (), e.message);
        }
    }

    protected async File get_source_file (Cancellable? cancellable)  throws GLib.Error {
        installer.configure_install_script (script);
        var output_dir = File.new_for_path (get_user_pkgcache ());

        unattended_tmp = yield script.generate_output_async (installer.os, installer.config, output_dir, cancellable);

        return unattended_tmp;
    }
}

private class Boxes.UnattendedAvatarFile : GLib.Object, Boxes.UnattendedFile {
    public string dest_name { get; set; }
    public string src_path { get; set; }

    protected UnattendedInstaller installer  { get; set; }

    private File unattended_tmp;

    private AvatarFormat? avatar_format;
    private Gdk.PixbufFormat pixbuf_format;

    public UnattendedAvatarFile (UnattendedInstaller installer, string src_path, AvatarFormat? avatar_format)
                                 throws Boxes.Error {
        this.installer = installer;
        this.src_path = src_path;

        this.avatar_format = avatar_format;

        foreach (var format in Gdk.Pixbuf.get_formats ()) {
            if (avatar_format != null) {
                foreach (var mime_type in avatar_format.mime_types) {
                    if (mime_type in format.get_mime_types ()) {
                        pixbuf_format = format;

                        break;
                    }
                }
            } else if (format.get_name () == "png")
                pixbuf_format = format; // Fallback to PNG if supported

            if (pixbuf_format != null)
                break;
        }

        if (pixbuf_format == null)
            throw new Boxes.Error.INVALID ("Failed to find suitable format to save user avatar file in.");

        dest_name = installer.username + "." + pixbuf_format.get_extensions ()[0];
    }

    ~UnattendedAvatarFile () {
        if (unattended_tmp == null)
            return;

        try {
            delete_file (unattended_tmp);
        } catch (GLib.Error e) {
            warning ("Error deleting %s: %s", unattended_tmp.get_path (), e.message);
        }
    }

    protected async File get_source_file (Cancellable? cancellable) throws GLib.Error {
        var destination_path = installer.get_user_unattended (dest_name);

        try {
            var width = (avatar_format != null)? avatar_format.width : -1;
            var height = (avatar_format != null)? avatar_format.height : -1;
            var pixbuf = new Gdk.Pixbuf.from_file_at_scale (src_path, width, height, true);

            if (avatar_format != null && !avatar_format.alpha && pixbuf.get_has_alpha ())
                pixbuf = remove_alpha (pixbuf);

            debug ("Saving user avatar file at '%s'..", destination_path);
            pixbuf.save (destination_path, pixbuf_format.get_name ());
            debug ("Saved user avatar file at '%s'.", destination_path);
        } catch (GLib.Error error) {
            warning ("Failed to save user avatar: %s.", error.message);
        }

        unattended_tmp = File.new_for_path (destination_path);

        return unattended_tmp;
    }
}
