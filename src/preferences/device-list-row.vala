// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/device-list-row.ui")]
private class Boxes.DeviceListRow : Hdy.ActionRow {
    [GtkChild]
    private unowned Gtk.Switch toggle;

    public DeviceListRow (Boxes.UsbDevice device) {
        title = device.title;

        toggle.set_active (device.active);
        device.bind_property ("active", toggle, "active", BindingFlags.BIDIRECTIONAL);
    }
}

class Boxes.UsbDevice : GLib.Object {
    public string title;
    public bool active { get; set; }
}
