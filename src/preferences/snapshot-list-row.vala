// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/snapshot-list-row.ui")]
private class Boxes.SnapshotListRow : Hdy.ActionRow {
    public signal void display_toast (Boxes.Toast toast);
    public signal void is_current ();

    public GVir.DomainSnapshot snapshot;
    public string activity_message { get; set; default = ""; }

    [GtkChild]
    private unowned Gtk.Label name_label;
    [GtkChild]
    private unowned Gtk.Label description_label;
    [GtkChild]
    private unowned Gtk.Stack mode_stack;
    [GtkChild]
    private unowned Gtk.Entry name_entry;
    [GtkChild]
    private unowned Gtk.Box edit_name_box;
    [GtkChild]
    private unowned Gtk.Box show_name_box;

    private Boxes.LibvirtMachine machine;
    private unowned Gtk.Container? parent_container = null;

    construct {
        this.parent_set.connect (() => {
            var parent = get_parent () as Gtk.Container;

            if (parent == null)
                return;

            this.parent_container = parent;
        });
    }

    public SnapshotListRow (GVir.DomainSnapshot snapshot,
                            LibvirtMachine      machine) {
        this.snapshot = snapshot;
        this.machine = machine;

        try {
            setup_labels (snapshot.get_config (0));
        } catch (GLib.Error e) {
            critical (e.message);

            display_toast (new Boxes.Toast (e.message));
        }
    }

    private void setup_labels (GVirConfig.DomainSnapshot config, string? name = null) {
        name_label.label = (name == null) ? config.get_description () : name;

        var date = new DateTime.from_unix_local (config.get_creation_time ());
        var date_string = date.format ("%x, %X");
        if (date_string != config.get_description ()) {
            description_label.visible = true;
            description_label.label = date_string;
        }
    }

    [GtkCallback]
    private void on_save_name_button_clicked () {
        var name = name_entry.text;

        try {
            var config = snapshot.get_config (0);
            config.set_description (name);
            snapshot.set_config (config);
            setup_labels (config, name);
            mode_stack.visible_child = show_name_box;
        } catch (GLib.Error e) {
            warning ("Failed to rename snapshot to %s: %s", name, e.message);

            // Translators: %s is the reason why Boxes failed to rename the snapshot.
            display_toast (new Boxes.Toast (_("Failed to rename snapshot: %s").printf (e.message)));
        }
    }


    [GtkCallback]
    private void on_revert_button_clicked () {
        var snapshot_name = this.snapshot.get_name ();
        var snapshot_state = GVirConfig.DomainSnapshotDomainState.NOSTATE;

        try {
            var snapshot_config = snapshot.get_config (0);
            snapshot_name = snapshot_config.get_description ();
            snapshot_state = snapshot_config.get_state ();
        } catch (GLib.Error e) {}

        activity_message = _("Reverting to %s…").printf (snapshot_name);

        if (machine.window.previous_ui_state == UIState.DISPLAY &&
            snapshot_state == GVirConfig.DomainSnapshotDomainState.SHUTOFF) {
            // Previous UI state being DISPLAY implies that machine is running
            ulong restart_id = 0;
            restart_id = machine.domain.stopped.connect (() => {
                machine.start.begin (Machine.ConnectFlags.NONE, null);
                machine.domain.disconnect (restart_id);
            });
        }

        snapshot.revert_to_async.begin (0, null, (obj, res) => {
            try {
                snapshot.revert_to_async.end (res);
                parent_container.queue_draw ();

                is_current ();
            } catch (GLib.Error e) {
                warning (e.message);

                // Translators: %s is the reason why Boxes failed to apply the snapshot.
                display_toast (new Boxes.Toast (_("Failed to revert to snapshot: %s").printf (e.message)));
            }
            activity_message = null;
        });
    }


    [GtkCallback]
    private void on_delete_button_clicked () {
        string snapshot_identifier = snapshot.get_name ();
        try {
            var config = snapshot.get_config (0);
            snapshot_identifier = config.get_description ();
        } catch (GLib.Error e) {
            warning ("Could not get configuration of snapshot %s: %s",
                      snapshot.get_name (),
                      e.message);
        }
        var message = _("Snapshot “%s” deleted.").printf (snapshot_identifier);
        parent_container = (Gtk.Container) this.get_parent ();
        var row = this;
        parent_container.remove (this);

        Toast.OKFunc undo = () => {
            parent_container.add (this);
            row = null;
        };

        Toast.DismissFunc really_remove = () => {
            this.snapshot.delete_async.begin (0, null, (obj, res) =>{
                try {
                    this.snapshot.delete_async.end (res);
                    parent_container.queue_draw ();
                } catch (GLib.Error e) {
                    warning ("Error while deleting snapshot %s: %s", snapshot.get_name (), e.message);
                }
            });
            row = null;
        };

        display_toast (new Boxes.Toast () {
            message = message,
            action = _("Undo"),
            undo_func = (owned) undo,
            dismiss_func = (owned) really_remove,
        });
    }

    [GtkCallback]
    private void on_rename_button_clicked () {
        name_entry.text = name_label.get_text ();
        mode_stack.visible_child = edit_name_box;
        name_entry.grab_focus ();
    }
}
