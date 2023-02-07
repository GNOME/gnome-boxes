// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/firmware-row.ui")]
private class Boxes.FirmwareRow : Hdy.ActionRow {
    [GtkChild]
    private unowned Gtk.RadioButton uefi_button;

    public bool is_uefi {
        get {
            return uefi_button.get_active ();
        }
    }
}
