// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/thumbnail.ui")]
private class Boxes.Thumbnail: Gtk.Box {
    [GtkChild]
    private unowned Gtk.Stack stack;
    [GtkChild]
    private unowned Gtk.Spinner spinner_thumbnail;
    [GtkChild]
    private unowned Gtk.Image live_thumbnail;
    [GtkChild]
    private unowned Gtk.Box blank_thumbnail;
    [GtkChild]
    private unowned Gtk.Image emblem;
    private string emblem_icon_name {
        set {
            emblem.icon_name = value + "-symbolic";
        }
    }
    public int emblem_size {
        set {
            emblem.icon_size = value;
        }
    }

    public void update (Machine machine) {
        if (machine.under_construction) {
            stack.visible_child = spinner_thumbnail;

            return;
        }

        if (machine.pixbuf != null && !machine.is_stopped) {
            machine.take_screenshot.begin ((source, result) => {
                try {
                    var screenshot = machine.take_screenshot.end (result);

                    /* machine is stopping / stopped */
                    if (screenshot == null)
                        return;

                    var scaled = screenshot.scale_simple (width_request,
                                                          height_request,
                                                          Gdk.InterpType.BILINEAR);
                    live_thumbnail.set_from_pixbuf (scaled);
                    stack.visible_child = live_thumbnail;
                    debug ("Updating thumbnail with image!");
                } catch (GLib.Error error) {
                    debug (error.message);
                }
            });

            return;
        }

        stack.visible_child = blank_thumbnail;
        var libvirt_machine = machine as LibvirtMachine;
        if (VMConfigurator.is_live_config (libvirt_machine.domain_config)) {
            emblem_icon_name = "media-optical";
        } else if (machine.is_stopped) {
            emblem_icon_name = "system-shutdown";
        } else {
            emblem_icon_name = "computer";
        }

        debug ("Updating thumbnail with '%s' icon!", emblem.icon_name);
    }
}
