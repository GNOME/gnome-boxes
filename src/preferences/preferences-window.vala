// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/preferences-window.ui")]
private class Boxes.PreferencesWindow : Hdy.PreferencesWindow {
    public Machine machine {
        set {
            resources_page.setup (value as LibvirtMachine);
            devices_page.setup (value as LibvirtMachine);
            snapshots_page.setup (value as LibvirtMachine);
        }
    }

    [GtkChild]
    private unowned Boxes.ResourcesPage resources_page;
    [GtkChild]
    private unowned Boxes.DevicesPage devices_page;
    [GtkChild]
    private unowned Boxes.SnapshotsPage snapshots_page;

    public void show_troubleshoot_logs () {
        resources_page.show_logs ();
    }
}
