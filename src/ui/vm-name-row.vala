// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/vm-name-row.ui")]
private class Boxes.VMNameRow : Hdy.PreferencesRow {
    [GtkChild]
    private unowned Gtk.Entry entry;
    public string text { get; set; }

    construct {
        bind_property ("text", entry, "text", BindingFlags.BIDIRECTIONAL);
    }
}
