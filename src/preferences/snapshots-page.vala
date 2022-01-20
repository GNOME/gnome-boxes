// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/snapshots-page.ui")]
private class Boxes.SnapshotsPage : Hdy.PreferencesPage {
    private LibvirtMachine machine;

    [GtkChild]
    private unowned Boxes.ToastOverlay toast_overlay;

    [GtkChild]
    private unowned Hdy.PreferencesGroup preferences_group;

    [GtkChild]
    private unowned Gtk.Stack stack;
    [GtkChild]
    private unowned Gtk.ListBox listbox;
    [GtkChild]
    private unowned Gtk.Box activity_page;
    [GtkChild]
    private unowned Gtk.Label activity_label;

    private Gtk.Button add_button;

    private string? activity {
        set {
            if (value == null) {
                stack.visible_child = listbox;
            } else {
                activity_label.label = value;
                stack.visible_child = activity_page;
            }
        }
    }

    public void setup (LibvirtMachine machine) {
        this.machine = machine;

        listbox.set_sort_func (config_sort_func);

        destroy.connect (() => { fetch_snapshots_cancellable.cancel (); });
        fetch_snapshots.begin ();

        add_button = new Gtk.Button () {
            visible = true,
            image = new Gtk.Image () {
                visible = true,
                icon_name = "list-add-symbolic"
            }
        };
        add_button.get_style_context ().add_class ("flat");
        add_button.clicked.connect (create_snapshot);
        listbox.add (add_button);

        update_snapshot_stack_page ();
    }

    private GLib.Cancellable fetch_snapshots_cancellable = new GLib.Cancellable ();
    private async void fetch_snapshots () {
        try {
            yield machine.domain.fetch_snapshots_async (GVir.DomainSnapshotListFlags.ALL,
                                                        fetch_snapshots_cancellable);
            var snapshots =  machine.domain.get_snapshots ();
            foreach (var snapshot in snapshots) {
                listbox.add (create_snapshot_row (snapshot));
            }
        } catch (GLib.Error e) {
            warning ("Could not fetch snapshots: %s", e.message);
        }
    }

    private SnapshotListRow create_snapshot_row (GVir.DomainSnapshot snapshot) {
        var row = new SnapshotListRow (snapshot, machine);
        row.notify["activity-message"].connect (row_activity_changed);
        row.display_toast.connect ((toast) => {
            toast_overlay.display_toast (toast);
        });
        row.is_current.connect (select_row);

        try {
            bool is_current = false;
            if (snapshot.get_is_current (0, out is_current)) {
                row.selectable = is_current;
                if (is_current)
                    select_row (row);
            }
        } catch (GLib.Error error) {
            warning ("Failed to determine whether '%s' is the current snapshot: %s",
                     snapshot.get_name (), error.message);
        }

        return row;
    }

    private void select_row (SnapshotListRow selected_row) {
        // We want only the last created snapshot to be selectable
        foreach (var child in listbox.get_children ()) {
            if (child is SnapshotListRow) {
                var row = child as SnapshotListRow;
                row.selectable = false;
            }
        }

        selected_row.selectable = true;
        listbox.select_row (selected_row);
    }

    private int config_sort_func (Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
        if (row1.get_child () == add_button)
            return 1;
        if (row2.get_child () == add_button)
            return 1;

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

    private async void create_snapshot () {
        if (machine.state == Machine.MachineState.RUNNING)
            this.activity = _("Creating new snapshot…");

        try {
            var new_snapshot = yield machine.create_snapshot ();
            listbox.add (create_snapshot_row (new_snapshot));
        } catch (GLib.Error e) {
            var msg = _("Failed to create snapshot of %s").printf (machine.name);
            warning (e.message);

            toast_overlay.display_toast (new Boxes.Toast (msg));
        }
        this.activity = null;

        update_snapshot_stack_page ();
    }

    private void row_activity_changed (GLib.Object source, GLib.ParamSpec param_spec) {
        var row = source as SnapshotListRow;
        this.activity = row.activity_message;
    }

    [GtkCallback]
    private void update_snapshot_stack_page () {
        var num_rows = listbox.get_children ().length ();

        // we need to account for the "+" button
        if (num_rows > 1) {
           preferences_group.description = _("Revert to a previous state of your box.");
        } else {
           preferences_group.description = _("Use the button below to create your first snapshot.");
        }
    }
}
