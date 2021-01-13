// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/preferences-dialog.ui")]
private class Boxes.PreferencesDialog: Hdy.PreferencesWindow {
    private unowned AppWindow app_window;

    [GtkChild]
    private PreferencesResourcesPage resources_page;
    [GtkChild]
    private PreferencesDevicesPage devices_page;
    [GtkChild]
    private PreferencesSnapshotsPage snapshots_page;

    public PreferencesDialog (AppWindow app_window, Machine machine) {
        set_transient_for (app_window);
        this.app_window = app_window;

        resources_page.setup (machine as LibvirtMachine);
        devices_page.setup (machine as LibvirtMachine);
        snapshots_page.setup (machine as LibvirtMachine);
    }

    [GtkCallback]
    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        var default_modifiers = Gtk.accelerator_get_default_mod_mask ();
        var direction = get_direction ();

        if (((direction == Gtk.TextDirection.LTR && // LTR
              event.keyval == Gdk.Key.Left) ||      // ALT + Left -> back
             (direction == Gtk.TextDirection.RTL && // RTL
              event.keyval == Gdk.Key.Right)) &&    // ALT + Right -> back
            (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            //topbar.click_back_button ();

            return true;
        } else if (event.keyval == Gdk.Key.Escape) { // ESC -> back
            //revert_state ();

            return true;
        }

        return false;
    }
}
