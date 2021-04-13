[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/installation-summary.ui")]
private class Boxes.InstallationSummary: Gtk.Grid {
    public delegate void CustomizeFunc ();

    private int current_row;

    construct {
        current_row = 0;
    }

    public void add_property (string name, string? value) {
        if (value == null)
            return;

        var label_name = new Gtk.Label (name);
        label_name.get_style_context ().add_class ("dim-label");
        label_name.halign = Gtk.Align.END;
        attach (label_name, 0, current_row, 1, 1);

        var label_value = new Gtk.Label (value);
        label_value.set_ellipsize (Pango.EllipsizeMode.END);
        label_value.set_max_width_chars (32);
        label_value.halign = Gtk.Align.START;
        attach (label_value, 1, current_row, 1, 1);

        current_row += 1;
        show_all ();
    }

    public void clear () {
        foreach (var child in get_children ()) {
            remove (child);
        }

        current_row = 0;
    }
}
