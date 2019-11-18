// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

public class Boxes.DownloadsHub : Gtk.MenuButton {
    private static DownloadsHub downloads_hub;

    private GLib.ListStore model = new GLib.ListStore (typeof (Osinfo.Media));

    private DownloadsHubPopover hub;

    public static DownloadsHub get_instance () {
        if (downloads_hub == null)
            downloads_hub = new DownloadsHub ();

        return downloads_hub;
    }

    construct {
        hub = new Boxes.DownloadsHubPopover ();
        hub.relative_to = this;

        this.popover = hub;
    }

    public void add_item (WizardDownloadableEntry entry) {
        var label = new Gtk.Label (entry.title);
        label.visible = true;

        hub.add_item (label);
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/downloads-hub-popover.ui")]
private class Boxes.DownloadsHubPopover : Gtk.Popover {
    [GtkChild]
    private ListBox listbox;

    public DownloadsHubPopover () {
    }

    public void add_item (Gtk.Widget entry) {
        listbox.insert (entry, -1);
    }
}
