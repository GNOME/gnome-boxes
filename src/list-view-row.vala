// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/list-view-row.ui")]
private class Boxes.ListViewRow: Hdy.ActionRow {
    public const int SCREENSHOT_WIDTH = 60;
    public const int SCREENSHOT_HEIGHT = 45;

    public CollectionItem item { get; private set; }
    private Machine machine {
        get { return item as Machine; }
    }

    [GtkChild]
    private unowned Gtk.Stack stack;
    [GtkChild]
    private unowned Gtk.Image thumbnail;
    [GtkChild]
    private unowned Gtk.Image running_thumbnail;
    [GtkChild]
    private unowned Gtk.EventBox spinner_box;
    [GtkChild]
    private unowned Gtk.Spinner spinner;

    private Boxes.MachineThumbnailer thumbnailer;

    public ListViewRow (CollectionItem item) {
        this.item = item;

        thumbnailer = new MachineThumbnailer (machine,
                                              SCREENSHOT_WIDTH,
                                              SCREENSHOT_HEIGHT);

        stack.width_request = SCREENSHOT_WIDTH;
        stack.height_request = SCREENSHOT_HEIGHT;

        machine.notify["under-construction"].connect (update_thumbnail);
        machine.notify["is-stopped"].connect (update_thumbnail);
        machine.notify["state"].connect (update_status);
        machine.notify["status"].connect (update_status);
        thumbnailer.notify["thumbnail"].connect (update_thumbnail);

        update_thumbnail ();
        update_status ();

        machine.bind_property ("name", this, "title", BindingFlags.SYNC_CREATE);
    }

    private void update_thumbnail () {
        var libvirt_machine = machine as LibvirtMachine;

        running_thumbnail.set_from_pixbuf (thumbnailer.thumbnail);

        if (machine.under_construction) {
            stack.visible_child = spinner_box;
            spinner.start ();

            return;
        } else if (thumbnailer.thumbnail != null) {
            stack.visible_child = running_thumbnail;
        } else {
            if (VMConfigurator.is_live_config (libvirt_machine.domain_config))
                thumbnail.icon_name = "media-optical-symbolic";
            else if (machine.is_stopped)
                thumbnail.icon_name = "system-shutdown-symbolic";
            else
                thumbnail.icon_name = "computer-symbolic";

            stack.visible_child = thumbnail;
        }

        spinner.stop ();
    }

    private void update_status () {
        if (machine.status != null) {
            subtitle = machine.status;

            return;
        }

        if (machine.is_running) {
            subtitle = _("Running");

            return;
        }

        if (machine.is_on) {
            subtitle = _("Paused");

            return;
        }

        subtitle = _("Powered Off");
    }
}
