using Gtk;
using Hdy;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/review-page.ui")]
private class Boxes.AssistantReviewPage : AssistantPage {
    [GtkChild]
    private unowned Gtk.InfoBar nokvm_infobar;
    [GtkChild]
    private unowned Hdy.ActionRow os_row;
    [GtkChild]
    private unowned Gtk.Label os_label;
    [GtkChild]
    private unowned Boxes.RamRow ram_row;
    [GtkChild]
    private unowned Boxes.StorageRow storage_row;
    [GtkChild]
    private unowned Hdy.ActionRow unattended_username_row;
    [GtkChild]
    private unowned Gtk.Label username_label;
    [GtkChild]
    private unowned Hdy.ActionRow unattended_password_row;
    [GtkChild]
    private unowned Gtk.Label password_label;
    [GtkChild]
    private unowned Hdy.ActionRow uefi_row;
    [GtkChild]
    private unowned Gtk.Switch uefi_switch;

    private GLib.Cancellable? cancellable;

    public async void setup (VMCreator vm_creator) {
        cancellable = new GLib.Cancellable ();

        try {
            artifact = yield vm_creator.create_vm (cancellable);
        } catch (IOError.CANCELLED cancel_error) { // We did this, so ignore!
        } catch (GLib.Error error) {
            warning ("Box setup failed: %s", error.message);
        }

        yield populate (artifact as LibvirtMachine);
    }

    public async void populate (LibvirtMachine machine) {
        var os = yield machine.get_os ();
        if (os != null) {
            os_row.visible = true;
            os_label.label = os.get_name ();
        }

        ram_row.setup (machine);
        storage_row.setup (machine);

        var install_media = machine.vm_creator.install_media;
        bool show_unattended_rows = false;
        if (install_media is Boxes.UnattendedInstaller) {
            var installer = install_media as Boxes.UnattendedInstaller;
            show_unattended_rows = installer.setup_box.express_toggle.active;

            if (!show_unattended_rows)
                return;

            username_label.label = installer.setup_box.username;
            password_label.label = installer.setup_box.hidden_password;
        }
        unattended_username_row.visible = unattended_password_row.visible = show_unattended_rows;

        uefi_row.visible = install_media.supports_efi;
    }

    [GtkCallback]
    private void on_uefi_switch_toggled () {
        LibvirtMachine machine = artifact as LibvirtMachine;
        bool use_uefi = uefi_switch.get_active ();

        try {
            InstallerMedia install_media = machine.vm_creator.install_media;
            install_media.set_uefi_firmware (machine.domain_config, use_uefi);

            machine.domain.set_config (machine.domain_config);
            debug ("Setting firmware to %s", use_uefi ? "EFI" : "BIOS");
        } catch (GLib.Error error) {
            warning ("Failed to toggle UEFI support: %s", error.message);
        }
    }

    public override void cleanup () {
        if (cancellable != null) {
            cancellable.cancel ();
            cancellable = null;
        }

        nokvm_infobar.hide ();

        if (artifact != null) {
            App.app.delete_machine (artifact as Machine);
        }
    }

    public override async void next () {
        if (artifact == null) {
            var wait = notify["artifact"].connect (() => {
                next.callback ();
            });
            yield;
            disconnect (wait);
        }

        done (artifact);

        cancellable.reset ();
    }
}
