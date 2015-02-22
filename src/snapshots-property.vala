// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.SnapshotsProperty : Boxes.Property {
    private LibvirtMachine machine;
    private Gtk.ListBox snapshot_list = new Gtk.ListBox ();
    private Gtk.Stack snapshot_stack;
    private Gtk.Label activity_label = new Gtk.Label ("");
    private Gtk.Box activity_box;
    private Gtk.Box snapshot_box;
    private string? activity {
        set {
            if (value == null) {
                snapshot_stack.visible_child = snapshot_box;
            } else {
                activity_label.label = value;
                snapshot_stack.visible_child = activity_box;
            }
        }
    }

    public SnapshotsProperty (LibvirtMachine machine) {
        var snapshot_stack = new Gtk.Stack ();
        snapshot_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;

        base (null, snapshot_stack, null);

        this.snapshot_stack = snapshot_stack;
        this.machine = machine;

        // Snapshots page
        snapshot_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        snapshot_box.margin = 20;

        var toolbar = new Gtk.Toolbar ();
        toolbar.get_style_context ().add_class (Gtk.STYLE_CLASS_INLINE_TOOLBAR);
        toolbar.icon_size = Gtk.IconSize.MENU;

        var create_snapshot_button = new Gtk.ToolButton (null, null);
        create_snapshot_button.clicked.connect (() => {
            create_snapshot.begin ();
        });
        var icon_img = new Gtk.Image.from_icon_name ("list-add-symbolic", Gtk.IconSize.MENU);
        create_snapshot_button.icon_widget = icon_img;
        toolbar.add (create_snapshot_button);

        snapshot_list.selection_mode = Gtk.SelectionMode.NONE;
        snapshot_list.set_size_request (-1, 250);
        snapshot_list.set_sort_func (config_sort_func);
        var snapshot_list_frame = new Gtk.Frame (null);
        snapshot_list_frame.add (snapshot_list);
        snapshot_box.pack_start (snapshot_list_frame, true, true);
        snapshot_box.pack_start (toolbar, true, false);
        snapshot_stack.add (snapshot_box);

        // Activity page
        activity_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        activity_box.valign = Gtk.Align.CENTER;
        var activity_spinner = new Gtk.Spinner ();
        activity_spinner.set_size_request (64, 64);
        activity_spinner.start ();
        activity_box.pack_start (activity_spinner, false, false);
        activity_label.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);
        activity_box.pack_start (activity_label, false, false);
        snapshot_stack.add (activity_box);

        fetch_snapshots.begin ();
    }

    private async void fetch_snapshots () {
        try {
            yield machine.properties.fetch_snapshots (null);
            var snapshots = machine.properties.get_snapshots ();

            foreach (var snapshot in snapshots) {
                var row = new SnapshotListRow (snapshot, machine);
                row.notify["activity-message"].connect (row_activity_changed);
                snapshot_list.add (row);
            }
        } catch (GLib.Error e) {
            warning ("Could not fetch snapshots: %s", e.message);
        }
    }

    private int config_sort_func (Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
        try {
            var conf1  = (row1 as SnapshotListRow).snapshot.get_config (0);
            var conf2  = (row2 as SnapshotListRow).snapshot.get_config (0);
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
            var new_snapshot = yield machine.properties.create_snapshot ();
            var new_row = new SnapshotListRow (new_snapshot, machine);
            new_row.notify["activity-message"].connect (row_activity_changed);
            snapshot_list.add (new_row);
        } catch (GLib.Error e) {
            var msg = _("Failed to create snapshot of %s").printf (machine.name);
            machine.window.notificationbar.display_error (msg);
            warning (e.message);
        }
        this.activity = null;
    }

    private void row_activity_changed (GLib.Object source, GLib.ParamSpec param_spec) {
        var row = source as SnapshotListRow;
        this.activity = row.activity_message;
    }
}
