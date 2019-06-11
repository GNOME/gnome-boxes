// This file is part of GNOME Boxes. License: LGPLv2+

using GVirConfig;
using Osinfo;

private class Boxes.UnattendedInstaller: InstallerMedia {
    public override bool need_user_input_for_vm_creation {
        get {
            // Whether the Express Install option should be displayed or not

            if (!os_media.supports_installer_script ())
                return false;

            var filter = new Filter ();
            filter.add_constraint (INSTALL_SCRIPT_PROP_PROFILE, INSTALL_SCRIPT_PROFILE_DESKTOP);

            var install_scripts = os_media.get_install_script_list ();
            if (install_scripts.get_length () > 0) {

                install_scripts = (install_scripts as Osinfo.List).new_filtered (filter) as InstallScriptList;
                if (install_scripts.get_length () > 0)
                    return true;

                return false;
            }

            install_scripts = os.get_install_script_list ();
            install_scripts = (install_scripts as Osinfo.List).new_filtered (filter) as InstallScriptList;
            if (install_scripts.get_length () > 0)
                return true;

            return false;
        }
    }

    public override bool ready_to_create {
        get {
            return setup_box.ready_to_create;
        }
    }

    public override Osinfo.DeviceList supported_devices {
        owned get {
            var devices = base.supported_devices;

            if (setup_box.express_install)
                return (devices as Osinfo.List).new_union (additional_devices) as Osinfo.DeviceList;
            else
                return devices;
        }
    }

    public bool needs_password {
        get {
            foreach (var s in scripts.get_elements ()) {
                var script = s as InstallScript;

                var param = script.get_config_param (INSTALL_CONFIG_PROP_USER_PASSWORD);
                if (param == null || param.is_optional ())
                    return false;
            }

            return true;
        }
    }

    public UnattendedSetupBox setup_box;

    public File? disk_file;           // Used for installer scripts, user avatar and pre-installation drivers
    public File? secondary_disk_file; // Used for post-installation drivers that won't fit on 1.44M primary disk
    public File? kernel_file;
    public File? initrd_file;
    public InstallConfig config;
    public InstallScriptList scripts;

    private GLib.List<UnattendedFile> unattended_files;
    private GLib.List<UnattendedFile> secondary_unattended_files;
    private UnattendedAvatarFile avatar_file;

    private string? timezone;
    private string lang;
    private string hostname;
    private string kbd;
    private bool driver_signing = true;

    // Devices made available by device drivers added through express installation (only).
    private Osinfo.DeviceList additional_devices;

    private static Fdo.Accounts? accounts;

    private InstallScriptInjectionMethod injection_method {
        private get {
            foreach (var unattended_file in unattended_files) {
                if (unattended_file is UnattendedScriptFile)
                    return (unattended_file as UnattendedScriptFile).injection_method;
            }

            return InstallScriptInjectionMethod.DISK;
        }
    }

    private static string escape_genisoimage_path (string path) {
        var str = path.replace ("\\", "\\\\");

        return str.replace ("=", "\\=");
    }

    construct {
        /* We can't do this in the class constructor as the sync call can
           cause deadlocks, see bug #676679. */
        if (accounts == null) {
            try {
                accounts = Bus.get_proxy_sync (BusType.SYSTEM,
                                               "org.freedesktop.Accounts",
                                               "/org/freedesktop/Accounts");
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
        config = new InstallConfig ("https://wiki.gnome.org/Boxes/unattended");

        unattended_files = new GLib.List<UnattendedFile> ();
        secondary_unattended_files = new GLib.List<UnattendedFile> ();
        var needs_internet = false;
        foreach (var s in scripts.get_elements ()) {
            var script = s as InstallScript;
            var filename = script.get_expected_filename ();
            add_unattended_file (new UnattendedScriptFile (this, script, filename));
            needs_internet = needs_internet || script.get_needs_internet ();
        }

        additional_devices = new Osinfo.DeviceList ();

        timezone = get_timezone ();
        lang = get_preferred_language ();
        kbd = get_preferred_keyboard (lang);

        var product_key_format = get_product_key_format ();
        setup_box = new UnattendedSetupBox (this, product_key_format, needs_internet);
        setup_box.notify["ready-to-create"].connect (() => {
            notify_property ("ready-to-create");
        });
        setup_box.user_wants_to_create.connect (() => {
            user_wants_to_create ();
        });

        fetch_user_avatar.begin ();
    }

    public override void prepare_to_continue_installation (string vm_name) {
        /*
         * A valid hostname format should be provided by libosinfo.
         * See: https://bugzilla.redhat.com/show_bug.cgi?id=1328236
         */
        this.hostname = replace_regex(vm_name, "[{|}~[\\]^':; <=>?@!\"#$%`()+/.,*&]", "");

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

    public override async void prepare_for_installation (string vm_name, Cancellable? cancellable) {
        setup_box.save_settings ();

        if (!setup_box.express_install) {
            debug ("Unattended installation disabled.");

            return;
        }

        prepare_to_continue_installation (vm_name);

        try {
            yield create_disk_image (cancellable);

            //FIXME: Linux-specific. Any generic way to achieve this?
            if (os_media.kernel_path != null && os_media.initrd_path != null) {
                var extractor = new ISOExtractor (device_file);

                yield extract_boot_files (extractor, cancellable);
            }

            foreach (var unattended_file in unattended_files)
                yield unattended_file.copy (cancellable);

            if (secondary_disk_file != null) {
                var secondary_disk_path = secondary_disk_file.get_path ();

                debug ("Creating secondary disk image '%s'...", secondary_disk_path);
                string[] argv = { "genisoimage", "-graft-points", "-J", "-rock", "-o", secondary_disk_path };
                foreach (var unattended_file in secondary_unattended_files) {
                    var dest_path = escape_genisoimage_path (unattended_file.dest_name);
                    var src_path = escape_genisoimage_path (unattended_file.src_path);

                    argv += dest_path + "=" + src_path;
                }

                yield exec (argv, cancellable);
                debug ("Created secondary disk image '%s'...", secondary_disk_path);
            }
        } catch (GLib.Error error) {
            clean_up ();
            // An error occurred when trying to setup unattended installation, but it's likely that a non-unattended
            // installation will work. When this happens, just disable unattended installs, and let the caller decide
            // if it wants to retry a non-automatic install or to just abort the box creation..
            setup_box.express_install = false;
            var msg = _("An error occurred during installation preparation. Express Install disabled.");
            App.app.main_window.notificationbar.display_error (msg);
            debug ("Disabling unattended installation: %s", error.message);
        }
    }

    public override void setup_domain_config (Domain domain) {
        base.setup_domain_config (domain);

        if (!setup_box.express_install)
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
        if (setup_box.password != null) {
            config.set_user_password (setup_box.password);
            config.set_admin_password (setup_box.password);
        }
        if (setup_box.username != null) {
            config.set_user_login (setup_box.username);
            config.set_user_realname (setup_box.username);
        }
        if (setup_box.product_key != null)
            config.set_reg_product_key (setup_box.product_key);
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
            config.set_target_disk (supports_virtio_disk || supports_virtio1_disk? "/dev/vda" : "/dev/sda");

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
        if (disk_file != null) {
            var path = disk_file.get_path ();
            remove_disk_from_domain_config (domain, path);
        }
        if (secondary_disk_file != null) {
            var path = secondary_disk_file.get_path ();
            remove_disk_from_domain_config (domain, path);
        }

        base.setup_post_install_domain_config (domain);
    }

    public override void populate_setup_box (Gtk.Box setup_box) {
        foreach (var child in setup_box.get_children ())
            setup_box.remove (child);

        setup_box.add (this.setup_box);
        setup_box.show ();
    }

    public override GLib.List<Pair<string,string>> get_vm_properties () {
        var properties = base.get_vm_properties ();

        if (setup_box.express_install) {
            properties.append (new Pair<string,string> (_("Username"), setup_box.username));
            properties.append (new Pair<string,string> (_("Password"), setup_box.hidden_password));
        }

        return properties;
    }

    public override void set_direct_boot_params (GVirConfig.DomainOs domain_os) {
        if (kernel_file == null || initrd_file == null)
            return;

        var script = scripts.get_nth (0) as InstallScript;

        domain_os.set_kernel (kernel_file.get_path ());
        domain_os.set_ramdisk (initrd_file.get_path ());
        domain_os.set_cmdline (script.generate_command_line_for_media (os_media, config));
    }

    public override void clean_up () {
        base.clean_up ();

        setup_box.clean_up ();

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

    public override async bool prepare (ActivityProgress progress = new ActivityProgress (),
                                        Cancellable?     cancellable = null) {
        return yield setup_drivers (progress, cancellable);
    }

    private DomainDisk? get_unattended_disk_config (PathFormat path_format = PathFormat.UNIX) {
        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_driver_name ("qemu");
        disk.set_driver_format (DomainDiskFormat.RAW);
        disk.set_source (disk_file.get_path ());

        if (injection_method == InstallScriptInjectionMethod.FLOPPY) {
            disk.set_target_dev ((path_format == PathFormat.DOS)? "A" : "fda");
            disk.set_guest_device_type (DomainDiskGuestDeviceType.FLOPPY);
            disk.set_target_bus (DomainDiskBus.FDC);
        } else {
            // Path format checks below are most probably practically redundant but a small price for future safety
            if (supports_virtio_disk || supports_virtio1_disk)
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
        disk.set_driver_format (DomainDiskFormat.RAW);
        disk.set_source (secondary_disk_file.get_path ());
        disk.set_target_dev ((path_format == PathFormat.DOS)? "E" : "hdd");
        disk.set_guest_device_type (DomainDiskGuestDeviceType.CDROM);
        disk.set_target_bus (prefers_q35? DomainDiskBus.SATA : DomainDiskBus.IDE);

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

    private async void create_disk_image (Cancellable? cancellable) throws GLib.Error {
        var template_path = get_unattended ("disk.img");
        var template_file = File.new_for_path (template_path);

        debug ("Creating disk image for unattended installation at '%s'..", disk_file.get_path ());
        yield template_file.copy_async (disk_file, FileCopyFlags.OVERWRITE, Priority.DEFAULT, cancellable);
        debug ("Floppy image for unattended installation created at '%s'", disk_file.get_path ());
    }

    private async void fetch_user_avatar () {
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

        if (!FileUtils.test (avatar_path, FileTest.EXISTS))
            return;

        setup_box.avatar_path = avatar_path;

        try {
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

    private async void extract_boot_files (ISOExtractor extractor, Cancellable? cancellable) throws GLib.Error {
        yield extractor.extract (os_media.kernel_path, kernel_file.get_path (), cancellable);
        yield extractor.extract (os_media.initrd_path, initrd_file.get_path (), cancellable);
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

    private async bool setup_drivers (ActivityProgress progress, Cancellable? cancellable = null) {
        progress.info = _("Downloading device drivers…");

        var scripts = get_pre_installer_scripts ();
        var drivers = get_pre_installable_drivers (scripts);

        if (drivers.length () != 0 && scripts.length () != 0) {
            var drivers_progress = progress.add_child_activity (0.5);
            if (!yield setup_drivers_from_list (drivers, drivers_progress, add_unattended_file, cancellable))
                return false;
        } else
            progress.progress = 0.5;

        scripts = get_post_installer_scripts ();
        drivers = get_post_installable_drivers (scripts);

        if (drivers.length () != 0 && scripts.length () != 0) {
            var drivers_progress = progress.add_child_activity (0.5);
            return yield setup_drivers_from_list (drivers, drivers_progress, add_secondary_unattended_file, cancellable);
        } else
            progress.progress = 1.0;

        return true;
    }

    private async bool setup_drivers_from_list (GLib.List<DeviceDriver> drivers,
                                                ActivityProgress        progress,
                                                AddUnattendedFileFunc   add_func,
                                                Cancellable?            cancellable = null) {
        var driver_progress_scale = 1d / drivers.length ();

        foreach (var driver in drivers) {
            var driver_progress = progress.add_child_activity (driver_progress_scale);
            try {
                yield setup_driver (driver, driver_progress, add_func, cancellable);
                additional_devices.add_all (driver.get_devices ());
            } catch (IOError.CANCELLED e) {
                debug ("Media preparation cancelled during driver setup.");

                return false;
            } catch (GLib.Error e) {
                debug ("Failed to make use of drivers at '%s': %s", driver.get_location (), e.message);
            } finally {
                driver_progress.progress = 1.0; // Ensure progress reaches 100%
            }
        }

        return true;
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

            var driver_file_name = location_checksum + "-" + file.get_basename ();
            var cached_path = get_drivers_cache (driver_file_name);
            var system_cached_path = get_system_drivers_cache (driver_file_name);

            string[] cached_paths = { cached_path };
            if (system_cached_path != null)
                cached_paths += system_cached_path;

            var file_progress = progress.add_child_activity (file_progress_scale);
            file = yield downloader.download (file, cached_paths, file_progress, cancellable);
            file_progress.progress = 1.0; // Ensure progress reaches 100%

            driver_files.append (new UnattendedRawFile (this, file.get_path (), filename));
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

    private string get_preferred_keyboard (string lang) {
        var os_db = MediaManager.get_instance ().os_db;
        var datamap = os_db.get_datamap ("http://x.org/x11-keyboard");
        string kbd_layout = null;

        try {
            var input_settings = new GLib.Settings ("org.gnome.desktop.input-sources");
            var sources = input_settings.get_value ("sources");

            if (sources != null) {
                kbd_layout = sources.get_child_value (0).get_child_value (1).get_string ();
            }

            if (datamap.reverse_lookup (kbd_layout) != null) {
                return kbd_layout;
            }
        } catch (GLib.Error error) {
            warning (error.message);
        }

        kbd_layout = datamap.lookup (lang);
        if (kbd_layout != null)
            return kbd_layout;

        return lang;
    }

    private string get_preferred_language () {
        var system_langs = Intl.get_language_names ();
        string[] media_langs = {};
        var media_langs_list = os_media.languages;

        foreach (var lang in media_langs_list)
            media_langs += lang;

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
