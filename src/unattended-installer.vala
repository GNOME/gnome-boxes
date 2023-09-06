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

                var osinfo_list = install_scripts as Osinfo.List;
                install_scripts = osinfo_list.new_filtered (filter) as InstallScriptList;
                if (install_scripts.get_length () > 0)
                    return true;

                return false;
            }

            install_scripts = os.get_install_script_list ();
            var osinfo_list = install_scripts as Osinfo.List;
            install_scripts = osinfo_list.new_filtered (filter) as InstallScriptList;
            if (install_scripts.get_length () > 0)
                return true;

            return false;
        }
    }

    public override Osinfo.DeviceList supported_devices {
        owned get {
            var devices = base.supported_devices;
            var osinfo_list = devices as Osinfo.List;

            return osinfo_list.new_union (additional_devices) as Osinfo.DeviceList;
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

    public File? disk_file;           // Used for installer scripts, user avatar, pre & post installation drivers
    public File? kernel_file;
    public File? initrd_file;
    public InstallConfig config;
    public InstallScriptList scripts;

    private GLib.List<UnattendedFile> unattended_files;
    private GLib.List<UnattendedFile> secondary_unattended_files;

    private string? timezone;
    private string lang;
    private string hostname;
    private string kbd;
    private bool driver_signing = true;

    // Devices made available by device drivers added through express installation (only).
    private Osinfo.DeviceList additional_devices;

    private InstallScriptInjectionMethod injection_method {
        private get {
            foreach (var unattended_file in unattended_files) {
                if (unattended_file is UnattendedScriptFile) {
                    var unattended_script_file = unattended_file as UnattendedScriptFile;

                    return unattended_script_file.injection_method;
                }
            }

            return InstallScriptInjectionMethod.DISK;
        }
    }

    private static string escape_genisoimage_path (string path) {
        var str = path.replace ("\\", "\\\\");

        return str.replace ("=", "\\=");
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
    }

    public override void prepare_to_continue_installation (string vm_name) {
        /*
         * A valid hostname format should be provided by libosinfo.
         * See: https://bugzilla.redhat.com/show_bug.cgi?id=1328236
         */
        this.hostname = replace_regex(vm_name, "[{|}~[\\]^':; <=>?@!\"#$%`()+/.,*&]", "");

        var unattended = "unattended.img";
        if (injection_method == InstallScriptInjectionMethod.CDROM)
            unattended = "unattended.iso";

        var path = get_user_unattended (unattended);
        disk_file = File.new_for_path (path);

        if (os_media.kernel_path != null && os_media.initrd_path != null) {
            path = get_user_unattended ("kernel");
            kernel_file = File.new_for_path (path);
            path = get_user_unattended ("initrd");
            initrd_file = File.new_for_path (path);
        }
    }

    public override async void prepare_for_installation (string vm_name, Cancellable? cancellable) {
        prepare_to_continue_installation (vm_name);

        try {
            if (injection_method == InstallScriptInjectionMethod.CDROM)
                yield create_iso (cancellable);
            else
                yield create_disk_image (cancellable);

            //FIXME: Linux-specific. Any generic way to achieve this?
            if (os_media.kernel_path != null && os_media.initrd_path != null) {
                var extractor = new ISOExtractor (device_file);

                yield extract_boot_files (extractor, cancellable);
            }

           if (injection_method != InstallScriptInjectionMethod.CDROM)
                foreach (var unattended_file in unattended_files)
                    yield unattended_file.copy (cancellable);
        } catch (GLib.Error error) {
            clean_up ();
            // An error occurred when trying to setup unattended installation, but it's likely that a non-unattended
            // installation will work. When this happens, just disable unattended installs, and let the caller decide
            // if it wants to retry a non-automatic install or to just abort the box creation..
            var msg = _("An error occurred during installation preparation. Express Install disabled.");
            App.app.main_window.display_toast (new Boxes.Toast (msg));
            debug ("Disabling unattended installation: %s", error.message);
        }
    }

    public override void setup_domain_config (Domain domain) {
        base.setup_domain_config (domain);

        return_if_fail (disk_file != null);
        var disk = get_unattended_disk_config ();
        domain.add_device (disk);
    }

    public string? username;
    public string? password;
    public string? product_key;
    public void configure_install_script (InstallScript script) {
        if (password != null) {
            config.set_user_password (password);
            config.set_admin_password (password);
        }
        if (username != null) {
            config.set_user_login (username);
            config.set_user_realname (username);
        }
        if (product_key != null)
            config.set_reg_product_key (product_key);
        if (timezone != null)
            config.set_l10n_timezone (timezone);
        config.set_l10n_language (lang);
        config.set_l10n_keyboard (kbd);
        config.set_hostname (hostname);
        config.set_hardware_arch (os_media.architecture);

        // The default preferred injection method, due to historical reasons,
        // is "disk". That's the reason we have to explicitly set the preferred
        // injection method to whatever we decide to use.
        // Explicitly setting it every time helps us to not forget this or that
        // case and is not that costly in the end.
        script.set_preferred_injection_method (injection_method);

        config.set_driver_signing (driver_signing);
    }

    public override void setup_post_install_domain_config (Domain domain) {
        if (disk_file != null) {
            var path = disk_file.get_path ();
            remove_disk_from_domain_config (domain, path);
        }

        base.setup_post_install_domain_config (domain);
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

        try {
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

    private DomainDisk? get_unattended_disk_config () {
        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_driver_name ("qemu");
        disk.set_driver_format (DomainDiskFormat.RAW);
        disk.set_source (disk_file.get_path ());

        if (injection_method == InstallScriptInjectionMethod.CDROM) {
            // Explicitly set "hdd" as the target device as the installer media is *always* set
            // as "hdc".
            disk.set_target_dev ("hdd");
            disk.set_guest_device_type (DomainDiskGuestDeviceType.CDROM);
            disk.set_target_bus (prefers_q35? DomainDiskBus.SATA : DomainDiskBus.IDE);
        } else {
            disk.set_target_dev ((supports_virtio_disk || supports_virtio1_disk)? "sda":  "sdb");
            disk.set_guest_device_type (DomainDiskGuestDeviceType.DISK);
            disk.set_target_bus (DomainDiskBus.USB);
        }

        return disk;
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
        yield template_file.copy_async (disk_file, FileCopyFlags.OVERWRITE | FileCopyFlags.TARGET_DEFAULT_PERMS, Priority.DEFAULT, cancellable);
        debug ("Floppy image for unattended installation created at '%s'", disk_file.get_path ());
    }

    private async void create_iso (Cancellable? cancellable) throws GLib.Error {
        var disk_file_path = disk_file.get_path ();

        debug ("Creating cdrom iso '%s'...", disk_file_path);
        string[] argv = { "genisoimage", "-graft-points", "-J", "-rock", "-o", disk_file_path };

        foreach (var unattended_file in unattended_files) {
            var source_file = yield unattended_file.get_source_file (cancellable);
            var dest_path = escape_genisoimage_path (unattended_file.dest_name);
            var src_path = escape_genisoimage_path (source_file.get_path());

            argv += dest_path + "=" + src_path;
        }

        foreach (var unattended_file in secondary_unattended_files) {
            var source_file = yield unattended_file.get_source_file (cancellable);
            var dest_path = escape_genisoimage_path (unattended_file.dest_name);
            var src_path = escape_genisoimage_path (source_file.get_path());

            argv += dest_path + "=" + src_path;
        }

        yield exec (argv, cancellable);
    }

    private async void extract_boot_files (ISOExtractor extractor, Cancellable? cancellable) throws GLib.Error {
        yield extractor.extract (os_media.kernel_path, kernel_file.get_path (), cancellable);
        yield extractor.extract (os_media.initrd_path, initrd_file.get_path (), cancellable);
    }

    public string? get_product_key_format () {
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
        var downloader = Downloader.get_default ();

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
        var os_db = MediaManager.get_default ().os_db;
        var datamap = os_db.get_datamap ("http://x.org/x11-keyboard");

        string? kbd_layout = get_preferred_keyboard_from_gsettings ();
        if (kbd_layout != null && datamap.reverse_lookup (kbd_layout) != null)
            return kbd_layout;

        kbd_layout = datamap.lookup (lang);
        if (kbd_layout != null)
            return kbd_layout;

        return lang;
    }

    private const string INPUT_SOURCE_SCHEMA = "org.gnome.desktop.input-sources";
    private string? get_preferred_keyboard_from_gsettings () {
        SettingsSchemaSource schema_source = SettingsSchemaSource.get_default ();

        var input_schema = schema_source.lookup (INPUT_SOURCE_SCHEMA, false);
        if (input_schema == null)
            return null;

        var input_settings = new GLib.Settings (INPUT_SOURCE_SCHEMA);
        var sources = input_settings.get_value ("sources");
        if (sources != null && sources.n_children () >= 1) {
            var sources_pair = sources.get_child_value (0);
            if (sources_pair != null) {
                var sources_pair_value = sources_pair.get_child_value (1);
                if (sources_pair_value != null)
                    return sources_pair_value.get_string ();
            }
        }

        return null;
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
