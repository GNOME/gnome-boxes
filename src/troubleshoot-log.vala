// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/troubleshoot-log.ui")]
private class Boxes.TroubleshootLog: Gtk.ScrolledWindow {
    [GtkChild]
    public unowned Gtk.TextView view;
}
