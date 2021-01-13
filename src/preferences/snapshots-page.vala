// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/snapshots-page.ui")]
private class Boxes.PreferencesSnapshotsPage: Boxes.PreferencesPage {
    private LibvirtMachine machine;

    [GtkChild]
    private Gtk.Stack stack;
    [GtkChild]
    private Gtk.ListBox list_page;
    [GtkChild]
    private Hdy.StatusPage empty_page;
    [GtkChild]
    private Gtk.Box activity_page;

    private string? activity {
        set {
            if (value == null) {
                stack.visible_child = list_page;
            } else {
                stack.visible_child = activity_page;
            }
        }
    }

    public void setup (LibvirtMachine machine) {
        this.machine = machine;

        list_page.set_sort_func (config_sort_func);

        fetch_snapshots.begin ();
    }

    private async void fetch_snapshots () {
        try {
            var snapshots = yield machine.properties.get_snapshots (null);

            foreach (var snapshot in snapshots) {
                list_page.add (create_snapshot_row (snapshot));
            }
        } catch (GLib.Error e) {
            warning ("Could not fetch snapshots: %s", e.message);
        }

        update_stack ();
    }

    private SnapshotListRow create_snapshot_row (GVir.DomainSnapshot snapshot) {
        var row = new SnapshotListRow (snapshot, machine);
        row.notify["activity-message"].connect (row_activity_changed);
        row.removed.connect (() => {
            row.visible = false;

            string snapshot_identifier = row.snapshot.get_name ();
            try {
                var config = row.snapshot.get_config (0);
                snapshot_identifier = config.get_description ();
            } catch (GLib.Error e) {
                warning ("Could not get configuration of snapshot %s: %s",
                          row.snapshot.get_name (),
                          e.message);
            }
            var message = _("Snapshot “%s” deleted.").printf (snapshot_identifier);

            Notification.OKFunc undo = () => {
                row.visible = true;

                active_notification = null;
            };

            Notification.DismissFunc really_remove = () => {
                row.really_remove ();
            };

            display_notification (message, _("Undo"), (owned) undo, (owned) really_remove);
        });

        return row;
    }

    [GtkCallback]
    private async void create_snapshot () {
        if (machine.state == Machine.MachineState.RUNNING)
            this.activity = _("Creating new snapshot…");

        try {
            var new_snapshot = yield machine.create_snapshot ();
            list_page.add (create_snapshot_row (new_snapshot));
        } catch (GLib.Error e) {
            var msg = _("Failed to create snapshot of %s").printf (machine.name);
            machine.window.notificationbar.display_error (msg);
            warning (e.message);
        }
        this.activity = null;
    }

    private void remove_snapshot (SnapshotListRow row) {
        row.visible = false;

        string snapshot_identifier = row.snapshot.get_name ();
        try {
            var config = row.snapshot.get_config (0);
            snapshot_identifier = config.get_description ();
        } catch (GLib.Error e) {
            warning ("Could not get configuration of snapshot %s: %s",
                      row.snapshot.get_name (),
                      e.message);
        }
        var message = _("Snapshot “%s” deleted.").printf (snapshot_identifier);

        Notification.OKFunc undo = () => {
            row.visible = true;
        };

        Notification.DismissFunc really_remove = () => {
            row.really_remove ();
        };

        display_notification (message, _("Undo"), (owned) undo, (owned) really_remove);
    }

    private void row_activity_changed (GLib.Object source, GLib.ParamSpec param_spec) {
        var row = source as SnapshotListRow;
        this.activity = row.activity_message;
    }

    [GtkCallback]
    private void update_stack () {
        var num_snapshots = list_page.get_children ().length ();
        if (num_snapshots > 0)
            stack.visible_child = list_page;
        else
            stack.visible_child = empty_page;
    }

    private int config_sort_func (Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
        try {
            var snapshot_row1 = row1 as SnapshotListRow;
            var snapshot_row2 = row2 as SnapshotListRow;

            var conf1  = snapshot_row1.snapshot.get_config (0);
            var conf2  = snapshot_row2.snapshot.get_config (0);
            if (conf1.get_creation_time () < conf2.get_creation_time ())
                return -1;
            else
                return 1;
        } catch (GLib.Error e) {
            warning ("Failed to fetch snapshot config: %s", e.message);
            return 0;
        }
    }
}
