// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/devices-page.ui")]
private class Boxes.PreferencesDevicesPage: Hdy.PreferencesPage {
    [GtkChild]
    private Boxes.SharedFoldersWidget shared_folders_widget;

    public void setup (LibvirtMachine machine) {
        shared_folders_widget.setup (machine.domain.get_uuid ());
    }
}
