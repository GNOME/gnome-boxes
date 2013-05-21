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

    public override Osinfo.DeviceList supported_devices {
        owned get {
            var devices = base.supported_devices;

            if (express_install)
                return (devices as Osinfo.List).new_union (additional_devices) as Osinfo.DeviceList;
            else
                return devices;
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

    public File? disk_file;           // Used for installer scripts, user avatar and pre-installation drivers
    public File? secondary_disk_file; // Used for post-installation drivers that won't fit on 1.44M primary disk
    public File? kernel_file;
    public File? initrd_file;
    public InstallConfig config;
    public InstallScriptList scripts;

    private string? product_key_format;

    private GLib.List<UnattendedFile> unattended_files;
    private GLib.List<UnattendedFile> secondary_unattended_files;
    private UnattendedAvatarFile avatar_file;

    private Gtk.Grid setup_grid;
    private int setup_grid_n_rows;

    private Gtk.Label setup_label;
    private Gtk.Box setup_hbox;
    private Gtk.Switch express_toggle;
    private Gtk.Entry username_entry;
    private Gtk.Entry password_entry;
    private Gtk.Entry key_entry;

    private string? timezone;
    private string lang;
    private string hostname;
    private string kbd;
    private bool driver_signing = true;

    // Devices made available by device drivers added through express installation (only).
    private Osinfo.DeviceList additional_devices;

    private ulong key_inserted_id; // ID of key_entry.insert_text signal handler

    private static Fdo.Accounts? accounts;

    private static string escape_mkisofs_path (string path) {
        var str = path.replace ("\\", "\\\\");

        return str.replace ("=", "\\=");
    }

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

    public UnattendedInstaller.from_media (InstallerMedia media, InstallScriptList scripts) throws GLib.Error {
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
        secondary_unattended_files = new GLib.List<UnattendedFile> ();
        foreach (var s in scripts.get_elements ()) {
            var script = s as InstallScript;
            var filename = script.get_expected_filename ();
            add_unattended_file (new UnattendedScriptFile (this, script, filename));
        }

        additional_devices = new Osinfo.DeviceList ();

        timezone = get_timezone ();
        lang = get_preferred_language ();
        kbd = lang;
        product_key_format = get_product_key_format ();

        setup_ui ();
    }

    public override void prepare_to_continue_installation (string vm_name) {
        this.hostname = vm_name.replace (" ", "-");

        var path = get_user_unattended ("unattended.img");
        disk_file = File.new_for_path (path);
        if (secondary_unattended_files.length () > 0) {
            path = get_user_unattended ("unattended.iso");
            secondary_disk_file = File.new_for_path (path);
        }

        if (os_media.kernel_path != null && os_media.initrd_path != null) {
            path = get_user_unattended ("kernel");
            kernel_file = File.new_for_path (path);
            path = get_user_unattended ("initrd");
            initrd_file = File.new_for_path (path);
        }
    }

    public override async void prepare_for_installation (string vm_name, Cancellable? cancellable) throws GLib.Error {
        if (!express_toggle.active) {
            debug ("Unattended installation disabled.");

            return;
        }

        prepare_to_continue_installation (vm_name);

        try {
            yield create_disk_image (cancellable);

            foreach (var unattended_file in unattended_files)
                yield unattended_file.copy (cancellable);

            if (secondary_disk_file != null) {
                var secondary_disk_path = secondary_disk_file.get_path ();

                debug ("Creating secondary disk image '%s'...", secondary_disk_path);
                string[] argv = { "mkisofs", "-graft-points", "-J", "-rock", "-o", secondary_disk_path };
                foreach (var unattended_file in secondary_unattended_files) {
                    var dest_path = escape_mkisofs_path (unattended_file.dest_name);
                    var src_path = escape_mkisofs_path (unattended_file.src_path);

                    argv += dest_path + "=" + src_path;
                }

                yield exec (argv, cancellable);
                debug ("Created secondary disk image '%s'...", secondary_disk_path);
            }

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
        }
    }

    public override void setup_domain_config (Domain domain) {
        base.setup_domain_config (domain);

        if (!express_toggle.active)
            return;

        return_if_fail (disk_file != null);
        var disk = get_unattended_disk_config ();
        domain.add_device (disk);
        if (secondary_disk_file != null) {
            disk = get_secondary_unattended_disk_config ();
            domain.add_device (disk);
        }
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
        if (timezone != null)
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

        var disk_config = get_unattended_disk_config (script.path_format);
        var device_path = device_name_to_path (script.path_format, disk_config.get_target_dev ());
        config.set_script_disk (device_path);

        if (avatar_file != null) {
            var location = ((script.path_format == PathFormat.UNIX)? "/" : "\\") + avatar_file.dest_name;
            config.set_avatar_location (location);
            config.set_avatar_disk (config.get_script_disk ());
        }

        config.set_pre_install_drivers_disk (config.get_script_disk ());
        if (secondary_disk_file != null) {
            disk_config = get_secondary_unattended_disk_config (script.path_format);
            device_path = device_name_to_path (script.path_format, disk_config.get_target_dev ());
            config.set_post_install_drivers_disk (device_path);
        }

        config.set_driver_signing (driver_signing);
    }

    public override void setup_post_install_domain_config (Domain domain) {
        var path = disk_file.get_path ();
        remove_disk_from_domain_config (domain, path);
        if (secondary_disk_file != null) {
            path = secondary_disk_file.get_path ();
            remove_disk_from_domain_config (domain, path);
        }

        base.setup_post_install_domain_config (domain);
    }

    public override void populate_setup_vbox (Gtk.Box setup_vbox) {
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

    public override void set_direct_boot_params (GVirConfig.DomainOs domain_os) {
        if (kernel_file == null || initrd_file == null)
            return;

        var script = scripts.get_nth (0) as InstallScript;

        domain_os.set_kernel (kernel_file.get_path ());
        domain_os.set_ramdisk (initrd_file.get_path ());
        domain_os.set_cmdline (script.generate_command_line (os, config));
    }

    public override void clean_up () {
        base.clean_up ();

        try {
            if (disk_file != null) {
                delete_file (disk_file);
                disk_file = null;
            }

            if (secondary_disk_file != null) {
                delete_file (secondary_disk_file);
                secondary_disk_file = null;
            }

            if (kernel_file != null) {
                delete_file (kernel_file);
                kernel_file = null;
            }

            if (initrd_file != null) {
                delete_file (initrd_file);
                initrd_file = null;
            }
        } catch (GLib.Error error) {
            debug ("Failed to clean-up: %s", error.message);
        }
    }

    public override void clean_up_preparation_cache () {
        base.clean_up_preparation_cache ();

        unattended_files = null;
        secondary_unattended_files = null;
    }

    public string get_user_unattended (string? suffix = null) {
        var filename = hostname;
        if (suffix != null)
            filename += "-" + suffix;

        return get_user_pkgcache (filename);
    }

    public override async void prepare (ActivityProgress progress = new ActivityProgress (),
                                        Cancellable? cancellable = null) {
        yield setup_drivers (progress, cancellable);
    }

    private void setup_ui () {
        setup_label = new Gtk.Label (_("Choose express install to automatically preconfigure the box with optimal settings."));
        setup_label.wrap = true;
        setup_label.width_chars = 30;
        setup_label.halign = Gtk.Align.START;
        setup_hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
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
        var express_label = new Gtk.Label (_("Express Install"));
        express_label.margin_right = 10;
        express_label.margin_bottom = 15;
        express_label.halign = Gtk.Align.END;
        express_label.valign = Gtk.Align.CENTER;
        setup_grid.attach (express_label, 0, 0, 2, 1);

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

        var label = new Gtk.Label (_("Username"));
        label.margin_right = 10;
        label.margin_bottom  = 10;
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.END;
        setup_grid.attach (label, 1, 1, 1, 1);
        username_entry = create_input_entry (Environment.get_user_name ());
        username_entry.margin_bottom  = 10;
        username_entry.halign = Gtk.Align.FILL;
        username_entry.valign = Gtk.Align.END;
        username_entry.activate.connect (() => {
            if (ready_for_express)
                user_wants_to_create ();
            else if (username != "" && product_key_format != null)
                key_entry.grab_focus (); // If username is provided, must be product key thats still not provided
        });

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
            password_entry.grab_focus ();
        });
        password_entry.focus_out_event.connect (() => {
            if (password_entry.text_length == 0)
                notebook.prev_page ();
            return false;
        });
        password_entry.activate.connect (() => {
            if (ready_for_express)
                user_wants_to_create ();
            else if (username == "")
                username_entry.grab_focus ();
            else if (product_key_format != null)
                key_entry.grab_focus ();
        });
        setup_grid.attach (notebook, 2, 2, 1, 1);
        setup_grid_n_rows++;

        foreach (var child in setup_grid.get_children ())
            if ((child != express_label) && (child != express_toggle))
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
        key_entry.activate.connect (() => {
            if (ready_for_express)
                user_wants_to_create ();
            else if (key_entry.text_length == product_key_format.length)
                username_entry.grab_focus (); // If product key is provided, must be username thats still not provided.
        });
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

    private DomainDisk? get_unattended_disk_config (PathFormat path_format = PathFormat.UNIX) {
        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("raw");
        disk.set_source (disk_file.get_path ());

        // FIXME: Ideally, we shouldn't need to check for distro
        if (os.distro == "win") {
            disk.set_target_dev ((path_format == PathFormat.DOS)? "A" : "fd");
            disk.set_guest_device_type (DomainDiskGuestDeviceType.FLOPPY);
            disk.set_target_bus (DomainDiskBus.FDC);
        } else {
            // Path format checks below are most probably practically redundant but a small price for future safety
            if (supports_virtio_disk)
                disk.set_target_dev ((path_format == PathFormat.UNIX)? "sda" : "E");
            else
                disk.set_target_dev ((path_format == PathFormat.UNIX)? "sdb" : "E");
            disk.set_guest_device_type (DomainDiskGuestDeviceType.DISK);
            disk.set_target_bus (DomainDiskBus.USB);
        }

        return disk;
    }

    private DomainDisk? get_secondary_unattended_disk_config (PathFormat path_format = PathFormat.UNIX) {
        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("raw");
        disk.set_source (secondary_disk_file.get_path ());
        disk.set_target_dev ((path_format == PathFormat.DOS)? "E" : "hdd");
        disk.set_guest_device_type (DomainDiskGuestDeviceType.CDROM);
        disk.set_target_bus (DomainDiskBus.IDE);

        return disk;
    }

    private string device_name_to_path (PathFormat path_format, string name) {
        return (path_format == PathFormat.UNIX)? "/dev/" + name : name;
    }

    private void add_unattended_file (UnattendedFile file) {
        unattended_files.append (file);
    }

    private void add_secondary_unattended_file (UnattendedFile file) {
        secondary_unattended_files.append (file);
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
        var template_path = get_unattended ("disk.img");
        var template_file = File.new_for_path (template_path);

        debug ("Creating disk image for unattended installation at '%s'..", disk_file.get_path ());
        yield template_file.copy_async (disk_file, FileCopyFlags.OVERWRITE, Priority.DEFAULT, cancellable);
        debug ("Floppy image for unattended installation created at '%s'", disk_file.get_path ());
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
        var src_file = File.new_for_path (src_path);
        yield copy_file (src_file, kernel_file, cancellable);

        src_path = extractor.get_absolute_path (os_media.initrd_path);
        src_file = File.new_for_path (src_path);
        yield copy_file (src_file, initrd_file, cancellable);
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

    private delegate void AddUnattendedFileFunc (UnattendedFile file);

    private async void setup_drivers (ActivityProgress progress, Cancellable? cancellable = null) {
        progress.info = _("Downloading device drivers...");

        var scripts = get_pre_installer_scripts ();
        var drivers = get_pre_installable_drivers (scripts);

        if (drivers.length () != 0 && scripts.length () != 0) {
            var drivers_progress = progress.add_child_activity (0.5);
            yield setup_drivers_from_list (drivers, drivers_progress, add_unattended_file, cancellable);
        } else
            progress.progress = 0.5;

        scripts = get_post_installer_scripts ();
        drivers = get_post_installable_drivers (scripts);

        if (drivers.length () != 0 && scripts.length () != 0) {
            var drivers_progress = progress.add_child_activity (0.5);
            yield setup_drivers_from_list (drivers, drivers_progress, add_secondary_unattended_file, cancellable);
        } else
            progress.progress = 1.0;
    }

    private async void setup_drivers_from_list (GLib.List<DeviceDriver> drivers,
                                                ActivityProgress        progress,
                                                AddUnattendedFileFunc   add_func,
                                                Cancellable?            cancellable = null) {
        var driver_progress_scale = 1d / drivers.length ();

        foreach (var driver in drivers) {
            var driver_progress = progress.add_child_activity (driver_progress_scale);
            try {
                yield setup_driver (driver, driver_progress, add_func, cancellable);
                additional_devices.add_all (driver.get_devices ());
            } catch (GLib.Error e) {
                debug ("Failed to make use of drivers at '%s': %s", driver.get_location (), e.message);
            } finally {
                driver_progress.progress = 1.0; // Ensure progress reaches 100%
            }
        }
    }

    private async void setup_driver (DeviceDriver          driver,
                                     ActivityProgress      progress,
                                     AddUnattendedFileFunc add_func,
                                     Cancellable?          cancellable) throws GLib.Error {
        var downloader = Downloader.get_instance ();

        var driver_files = new GLib.List<UnattendedFile> ();
        var location = driver.get_location ();
        var location_checksum = Checksum.compute_for_string (ChecksumType.MD5, location);
        var files = driver.get_files ();
        var file_progress_scale = 1d / files.length ();

        foreach (var filename in files) {
            var file_uri = location + "/" + filename;
            var file = File.new_for_uri (file_uri);

            var cached_path = get_drivers_cache (location_checksum + "-" + file.get_basename ());

            var file_progress = progress.add_child_activity (file_progress_scale);
            file = yield downloader.download (file, cached_path, file_progress);
            file_progress.progress = 1.0; // Ensure progress reaches 100%

            driver_files.append (new UnattendedRawFile (this, cached_path, filename));
        }

        // We don't do this in above loop to ensure we have all the driver files
        foreach (var driver_file in driver_files)
            add_func (driver_file);
    }

    private delegate bool DriverTestFunction (DeviceDriver driver);

    private GLib.List<DeviceDriver> get_pre_installable_drivers (GLib.List<InstallScript> preinst_scripts) {
        return get_installable_drivers (preinst_scripts,
                                        (driver) => { return driver.get_pre_installable (); },
                                        (script) => { return script.get_pre_install_drivers_signing_req (); });
    }

    private GLib.List<DeviceDriver> get_post_installable_drivers (GLib.List<InstallScript> postinst_scripts) {
        return get_installable_drivers (postinst_scripts,
                                        (driver) => { return !driver.get_pre_installable (); },
                                        (script) => { return script.get_post_install_drivers_signing_req (); });
    }

    private delegate bool DriverInstallableFunc (DeviceDriver driver);
    private delegate DeviceDriverSigningReq ScriptDriverSigningReqFunc (InstallScript script);

    private GLib.List<DeviceDriver> get_installable_drivers (GLib.List<InstallScript>   scripts,
                                                             DriverInstallableFunc      installable_func,
                                                             ScriptDriverSigningReqFunc signing_req_func) {

        var signing_required = false;
        foreach (var script in scripts)
            if (signing_req_func (script) != DeviceDriverSigningReq.NONE) {
                debug ("Script '%s' requires signed drivers.", script.id);
                signing_required = true;

                break;
            }

        var driver_signing_mutable = false;
        if (signing_required)
            // See if there is any script that will allow us to disable driver signing checks
            foreach (var s in this.scripts.get_elements ()) {
                var script = s as InstallScript;

                if (script.has_config_param_name (INSTALL_CONFIG_PROP_DRIVER_SIGNING)) {
                    debug ("Script '%s' allows disabling of driver signature checks.", script.id);
                    driver_signing_mutable = true;

                    break;
                }
            }

        return get_drivers ((driver) => {
            if (!installable_func (driver))
                return false;

            if (!driver.get_signed () && signing_required) {
                if (driver_signing_mutable)
                    driver_signing = false;
                else {
                    debug ("Driver from location '%s' is not signed. Ignoring..", driver.get_location ());

                    return false;
                }
            }

            return true;
        });
    }

    private GLib.List<DeviceDriver> get_drivers (DriverTestFunction test_func) {
        var drivers = new GLib.HashTable<string,DeviceDriver> (str_hash, str_equal);

        foreach (var d in os.get_device_drivers ().get_elements ()) {
            var driver = d as DeviceDriver;

            var compatibility = compare_cpu_architectures (os_media.architecture, driver.get_architecture ());
            var location = driver.get_location ();
            if (compatibility == CPUArchCompatibility.IDENTICAL)
                drivers.replace (location, driver);
            else if (compatibility == CPUArchCompatibility.COMPATIBLE && drivers.lookup (location) == null)
                drivers.insert (location, driver);
            // We don't entertain compatibility when word-size is different because 32-bit drivers
            // are not guaranteed to work on 64-bit architectures in all OSs.
        }

        // We can't just return drivers.get_values () as we don't own the list returned by this call and drivers
        // hashtable is destroyed at the end of this function. Also we can't just use drivers.get_values ().copy ()
        // as we need a deep copy of drivers.
        var ret = new GLib.List<DeviceDriver> ();
        foreach (var driver in drivers.get_values ()) {
            if (test_func (driver))
                ret.prepend (driver);
        }
        ret.reverse ();

        return ret;
    }

    private delegate bool ScriptTestFunction (InstallScript script);

    private GLib.List<InstallScript> get_pre_installer_scripts () {
        return get_scripts ((script) => { return script.get_can_pre_install_drivers (); });
    }

    private GLib.List<InstallScript> get_post_installer_scripts () {
        return get_scripts ((script) => { return script.get_can_post_install_drivers (); });
    }

    private GLib.List<InstallScript> get_scripts (ScriptTestFunction test_func) {
        var scripts = new GLib.List<InstallScript> ();

        foreach (var s in this.scripts.get_elements ()) {
            var script = s as InstallScript;

            if (test_func (script))
                scripts.append (script);
        }

        return scripts;
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
            debug ("Failed to match system locales with media languages, falling back to %s media language",
                   media_langs_list.nth_data (0));
            return media_langs_list.nth_data (0);
        }

        var lang = system_langs[0].replace (".utf8", "");
        lang = lang.replace (".UTF-8", "");
        debug ("No media language, using %s locale", lang);

        return lang;
    }

    private void remove_disk_from_domain_config (Domain domain, string disk_path) {
        var devices = domain.get_devices ();
        foreach (var device in devices) {
            if (!(device is DomainDisk))
                continue;

            var disk = device as DomainDisk;
            if (disk.get_source () == disk_path) {
                devices.remove (device);

                break;
            }
        }

        domain.set_devices (devices);
    }
}
