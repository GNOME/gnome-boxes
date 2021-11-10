// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/cdrom-row.ui")]
private class Boxes.CdromRow : Hdy.ActionRow {
    private LibvirtMachine machine;
    private GVirConfig.DomainDisk cdrom_config;

    [GtkChild]
    private unowned Gtk.Stack stack;
    [GtkChild]
    private unowned Gtk.Button select_button;
    [GtkChild]
    private unowned Gtk.Button remove_button;

    public void setup (LibvirtMachine machine) {
        this.machine = machine;

        foreach (var device_config in machine.domain_config.get_devices ()) {
            if (device_config is GVirConfig.DomainDisk) {
                var disk_config = device_config as GVirConfig.DomainDisk;
                var disk_type = disk_config.get_guest_device_type ();

                if (disk_type == GVirConfig.DomainDiskGuestDeviceType.CDROM) {
                    cdrom_config = disk_config;

                    break;
                }
            }
        }

        var source = cdrom_config.get_source ();
        if (source == null || source == "") {
            title = _("No CD/DVD image");

            stack.visible_child = select_button;

            return;
        }

        stack.visible_child = remove_button;
        title = get_utf8_basename (source);
    }

    private void set_cdrom_source_path (string? path = null) {
        cdrom_config.set_source (path != null ? path : "");

        try {
            machine.domain.update_device (cdrom_config, GVir.DomainUpdateDeviceFlags.CURRENT);

            // Let's also refresh the interface
            setup (machine);
        } catch (GLib.Error error) {
            debug ("Error inserting '%s' as CD into '%s': %s",
                   path,
                   machine.name,
                   error.message);
        }
    }

    [GtkCallback]
    private void on_select_button_clicked () {
        var file_chooser = new Gtk.FileChooserNative (_("Select a device or ISO file"),
                                                      get_toplevel () as Gtk.Window,
                                                      Gtk.FileChooserAction.OPEN,
                                                      _("Open"), _("Cancel"));
        var response = file_chooser.run ();
        if (response == Gtk.ResponseType.ACCEPT) {
            set_cdrom_source_path (file_chooser.get_filename ());
        }
    }

    [GtkCallback]
    private void on_remove_button_clicked () {
        set_cdrom_source_path (null);
    }
}
