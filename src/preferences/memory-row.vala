// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/memory-row.ui")]
private class Boxes.MemoryRow : Hdy.ActionRow {
    [GtkChild]
    protected unowned Gtk.Stack stack;
    [GtkChild]
    protected unowned Gtk.Label used_label;
    [GtkChild]
    public unowned Gtk.SpinButton spin_button;

    public uint64 memory {
        get {
            return (uint64)spin_button.get_value () / Osinfo.KIBIBYTES;
        }

        set {
            spin_button.set_value (value * Osinfo.KIBIBYTES);
        }
    }

    construct {
        spin_button.value_changed.connect (() => {
            notify_property ("memory");
        });
    }

    [GtkCallback]
    private int on_spin_button_input (Gtk.SpinButton spin_button, out double new_value) {
        uint64 current_value = (uint64)spin_button.get_value ();
        new_value = current_value;

        string? text = spin_button.get_text ();
        if (text == null)
            return 1;

        double user_input_value = double.parse (text);
        if (user_input_value == 0)
            return 1;

        new_value = user_input_value * Osinfo.GIBIBYTES;

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
