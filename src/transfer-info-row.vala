// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/transfer-info-row.ui")]
private class Boxes.TransferInfoRow: Gtk.Grid {
    [GtkChild]
    private unowned Gtk.Label status_label;
    [GtkChild]
    private unowned Gtk.Label details_label;
    [GtkChild]
    private unowned Gtk.Button cancel_button;
    [GtkChild]
    private unowned Gtk.ProgressBar progress_bar;
    [GtkChild]
    private unowned Gtk.Image done_image;

    public signal void finished ();

    public double progress {get; set; }
    public uint64 transferred_bytes {
        set {
            details_label.set_text ("%s / %s".printf (GLib.format_size (value), GLib.format_size (total_bytes)));
        }
    }
    public uint64 total_bytes { get; set; }

    public TransferInfoRow (string name) {
        progress = 0;

        // Translators: "%s" is a file name.
        var msg = _("Copying “%s” to “Downloads”".printf (trim_string (name)));
        status_label.set_text (msg);

        bind_property ("progress", progress_bar, "fraction", BindingFlags.BIDIRECTIONAL);
        cancel_button.clicked.connect (() => {
            finalize_transfer ();
            finished ();
        });
    }

    public void finalize_transfer () {
        cancel_button.image = done_image;
        cancel_button.set_sensitive (false);
        cancel_button.queue_draw ();
    }

    private string trim_string (string s) {
        if (s.length > 23)
            return s.substring (0, 15) + "…" + s.substring (-4, -1);

        return s;
    }
}
