// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/list-view-row.ui")]
private class Boxes.ListViewRow: Hdy.ActionRow {
    public CollectionItem item { get; private set; }
    private Machine machine {
        get { return item as Machine; }
    }

    [GtkChild]
    public unowned Boxes.Thumbnail thumbnail;
    [GtkChild]
    public unowned Gtk.Button menu_button;

    public signal void pop_context_menu ();

    public ListViewRow (CollectionItem item) {
        this.item = item;

        update_status ();
        machine.notify["state"].connect (update_status);
        machine.notify["status"].connect (update_status);

        update_thumbnail ();
        machine.notify["under-construction"].connect (update_thumbnail);
        machine.notify["is-stopped"].connect (update_thumbnail);
        machine.notify["pixbuf"].connect (update_thumbnail);

        machine.bind_property ("name", this, "title", BindingFlags.SYNC_CREATE);

        // This is a hack to align the "title" next to the "thumbnail".
        activatable_widget.get_parent ().hexpand = false;
    }

    private void update_thumbnail () {
        thumbnail.update (machine);
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

    [GtkCallback]
    public void pop_menu () {
        pop_context_menu ();
    }
}
