// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/memory-row.ui")]
private class Boxes.MemoryRow : Hdy.ActionRow {
    [GtkChild]
    protected unowned Gtk.Stack stack;
    [GtkChild]
    protected unowned Gtk.Label used_label;
    [GtkChild]
    public unowned Gtk.SpinButton spin_button;

    [GtkCallback]
    private int on_spin_button_input (Gtk.SpinButton spin_button, out double new_value) {
        uint64 current_value = (uint64)spin_button.get_value ();

        /* FIXME: we should be getting the value with spin_button.get_text () so we can
         * accept user manual input. This will require to parse the text properly and
         * convert strings such as 2.0 GiB into 2.0 * Osinfo.MEBIBYTE * 1024.
         *
         * As it is now, we don't support manual input, and the value can only be changed
         * by using the + and - buttons of the GtkSpinButton.
        */
        new_value = current_value;

        return 1;
    }

    [GtkCallback]
    private bool on_spin_button_output (Gtk.SpinButton spin_button) {
        uint64 current_value = (uint64)spin_button.get_value ();

        spin_button.text = GLib.format_size (current_value,
                                             GLib.FormatSizeFlags.IEC_UNITS);

        return true;
    }
}
