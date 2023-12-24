// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/assistant.ui")]
private class Boxes.Assistant : Hdy.Window {
    private InstallerMedia installer_media;
    private UnattendedInstaller unattended_installer;
    private Osinfo.Os? os {
        get {
            return installer_media.os;
        }
    }

    [GtkChild]
    private unowned Gtk.Stack pages;
    [GtkChild]
    private unowned Gtk.Box creating_page;
    [GtkChild]
    private unowned Gtk.Box error_page;
    [GtkChild]
    private unowned Hdy.StatusPage error_status_page;
    [GtkChild]
    private unowned Gtk.Box editing_page;
    [GtkChild]
    private unowned Gtk.Button create_button;
    [GtkChild]
    private unowned Boxes.VMNameRow name_entry;
    [GtkChild]
    private unowned Boxes.OsChooserRow os_chooser_row;
    [GtkChild]
    private unowned Boxes.FirmwareRow firmware_row;
    [GtkChild]
    private unowned Boxes.ExpressInstallRow express_install_row;
    [GtkChild]
    private unowned Boxes.RamRow ram_row;
    [GtkChild]
    private unowned Boxes.MemoryRow storage_limit_row;
    [GtkChild]
    private unowned Hdy.StatusPage creating_status_page;
    [GtkChild]
    private unowned Gtk.ProgressBar progress_bar;

    private GLib.Cancellable cancellable = new GLib.Cancellable ();

    public Assistant (AppWindow app_window, string path) {
        set_transient_for (app_window);

        setup.begin (path);
    }

    private async void setup (string path) {
        if (!yield check_libvirt_kvm ()) {
            show_error ("No KVM!\n");
            return;
        }

        yield prepare_for_path (path);
    }

    private async InstallerMedia? create_installer_media (string path) {
        var media_manager = MediaManager.get_default ();
        InstallerMedia? media = null;

        try {
            media = yield media_manager.create_installer_media_for_path (path, cancellable);
        } catch (GLib.Error error) {
            show_error (error.message);
        }

        return media;
    }

    private async void prepare_for_path (string path) {
        installer_media = yield create_installer_media (path);

        /* e.g. when media is not bootable */
        if (installer_media == null)
            return;

        if (installer_media.os != null) {
            os_chooser_row.select_os (os);
            os_chooser_row.subtitle = os.get_name ();
        } else {
            os_chooser_row.expanded = true;
        }

        update_rows ();
        pages.set_visible_child (editing_page);
    }

    private void update_rows () {
        name_entry.text = installer_media.label;
        firmware_row.visible = installer_media.supports_efi && !installer_media.requires_efi;

        if (os != null) {
            os_chooser_row.subtitle = os.get_vendor ();
        }

        setup_resource_rows ();
        express_install_row.visible = installer_media.supports_express_install; 
    }

    private void setup_resource_rows () {
        Osinfo.Resources? resources = null;

        if (os != null)
            resources = OSDatabase.get_recommended_resources_for_os (os);

        // fallback to default resources if we cannot detect the OS or
        // the detected OS hasn't provided any recommended resources
        if (resources == null)
            resources = OSDatabase.get_default_resources ();

        ram_row.memory = resources.ram / Osinfo.KIBIBYTES;

        try {
            var storage_pool = get_storage_pool (App.app.default_connection);
            var pool_info = storage_pool.get_info ();
            var max_storage = storage_limit_row.spin_button.get_value () + pool_info.available;

            storage_limit_row.spin_button.set_increments (256 * 1000 * 1000 , max_storage);
            storage_limit_row.spin_button.set_range (0, max_storage);
            storage_limit_row.memory = resources.storage / Osinfo.KIBIBYTES;
        } catch (GLib.Error error) {
            warning ("Failed to estimate maximum available storage: %s", error.message);
        }
    }

    [GtkCallback]
    private void setup_express_install_row () {
        if (!express_install_row.enabled)
            return;

        try {
            unattended_installer = (UnattendedInstaller)MediaManager.create_unattended_installer (installer_media);

            express_install_row.needs_password = unattended_installer.needs_password;
            express_install_row.product_key_format = unattended_installer.get_product_key_format ();

            create_button.sensitive = express_install_row.ready_to_install;
            express_install_row.credentials_changed.connect (() => {
                create_button.sensitive = express_install_row.ready_to_install;
            });
        } catch (GLib.Error error) {
            show_error (_("Failed to prepare express installation: %s").printf (error.message));
        }
    }

    [GtkCallback]
    private void on_os_selected_cb (Osinfo.Os? os) {
        installer_media.os = os;

        update_rows ();
    }

    private ActivityProgress create_preparation_progress () {
        var progress = new ActivityProgress ();
   
        progress.notify["progress"].connect (() => {
            if (progress.progress - progress_bar.fraction >= 0.01)
                progress_bar.fraction = progress.progress;
        }); 
        progress_bar.fraction = progress.progress = 0;

        return progress;
    }

    [GtkCallback]
    private async void on_create_button_clicked () {
        create_button.sensitive = false;
        try {
            if (express_install_row.enabled) {
                installer_media = unattended_installer;

                unattended_installer.username = express_install_row.username;
                unattended_installer.password = express_install_row.password;
                unattended_installer.product_key = express_install_row.product_key;

                // nothing here is slow except for "setting up drivers" for express-installs
                // no need to setup progress bars for regular vms.
                pages.set_visible_child (creating_page);
                var progress = create_preparation_progress ();
                progress.bind_property ("info", creating_status_page, "description");
                if (!yield installer_media.prepare (progress, cancellable)) {
                    create_button.sensitive = true;
                    return;
                }
            }

            var vm_creator = installer_media.get_vm_creator ();
            var machine = yield vm_creator.create_vm (cancellable);
            machine.title = name_entry.text;

            // Apply VM preferences
            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            config.memory = ram_row.memory;

            if (config.get_class ().find_property ("current-memory") != null)
                config.set ("current-memory", config.memory);

            machine.storage_volume.resize (storage_limit_row.memory * Osinfo.KIBIBYTES,
                                           GVir.StorageVolResizeFlags.SHRINK);
            if (firmware_row.is_uefi)
                installer_media.set_uefi_firmware (config, true);

            // save
            machine.domain.set_config (config);

            progress_bar.fraction = 1.0;

            // Start VM
            if (installer_media is UnattendedInstaller)
                machine.domain.start (0);
            else
                App.app.main_window.select_item (machine);
            vm_creator.launch_vm (machine);
            close ();
        } catch (GLib.Error error) {
            debug ("Failed to create virtual machine: %s", error.message);

            show_error (error.message);
        }
        create_button.sensitive = true;
    }

    private void show_error (string reason) {
        pages.set_visible_child (error_page);
        create_button.sensitive = false;
        error_status_page.description = reason;
    }

    public override void destroy () {
        cancellable.cancel ();

        base.destroy ();
    }
}
