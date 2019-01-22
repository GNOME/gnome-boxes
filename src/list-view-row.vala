// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/list-view-row.ui")]
private class Boxes.ListViewRow: Gtk.Box {
    public const int SCREENSHOT_WIDTH = 60;
    public const int SCREENSHOT_HEIGHT = 45;
    public const int CENTERED_EMBLEM_SIZE = 16;
    public const int EMBLEM_SIZE = 16;
    public const Gdk.RGBA FRAME_BORDER_COLOR = { 0x81 / 255.0, 0x85 / 255.0, 0x84 / 255.0, 1.0 };
    public const Gdk.RGBA FRAME_BACKGROUND_COLOR = { 0x4b / 255.0, 0x50 / 255.0, 0x50 / 255.0, 1.0 };

    public bool _selection_mode = false;
    public bool selection_mode {
        get { return _selection_mode; }
        set {
            _selection_mode = value;

            selection_button.visible = _selection_mode;

            if (!_selection_mode)
                selected = false;
        }
    }

    public bool _selected = false;
    public bool selected {
        get { return _selected; }
        set { _selected = selection_mode && value; }
    }

    public CollectionItem item { get; private set; }
    private Machine machine {
        get { return item as Machine; }
    }

    [GtkChild]
    private Gtk.CheckButton selection_button;
    [GtkChild]
    private Gtk.Stack stack;
    [GtkChild]
    private Gtk.Image thumbnail;
    [GtkChild]
    private Gtk.Spinner spinner;
    [GtkChild]
    private Gtk.Image favorite;
    [GtkChild]
    private Gtk.Label machine_name;
    [GtkChild]
    private Gtk.Label info_label;
    [GtkChild]
    private Gtk.Label status_label;

    private Boxes.MachineThumbnailer thumbnailer;

    private Binding selected_binding;

    public ListViewRow (CollectionItem item) {
        this.item = item;

        thumbnailer = new Boxes.MachineThumbnailer (machine,
                                                    SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT,
                                                    CENTERED_EMBLEM_SIZE, EMBLEM_SIZE);
        thumbnailer.favorite_emblem_enabled = false;
        thumbnailer.notify["thumbnail"].connect (() => {
            thumbnail.set_from_pixbuf (thumbnailer.thumbnail);
        });
        thumbnail.set_from_pixbuf (thumbnailer.thumbnail);

        selected_binding = bind_property ("selected", selection_button, "active", BindingFlags.BIDIRECTIONAL);

        machine.config.notify["categories"].connect (update_favorite);
        machine.notify["under-construction"].connect (update_thumbnail);
        machine.notify["info"].connect (update_info);
        machine.notify["state"].connect (update_status);
        machine.notify["status"].connect (update_status);

        update_thumbnail ();
        update_favorite ();
        update_info ();
        update_status ();

        machine.bind_property ("name", machine_name, "label", BindingFlags.SYNC_CREATE);
    }

    private void update_thumbnail () {
        if (machine.under_construction) {
            stack.visible_child = spinner;
            spinner.start ();
            spinner.visible = true;
        }
        else {
            stack.visible_child = thumbnail;
            spinner.stop ();
        }
    }

    private void update_favorite () {
        if ("favorite" in machine.config.categories)
            favorite.set_from_icon_name ("starred-symbolic", Gtk.IconSize.MENU);
        else
            favorite.clear ();
    }

    private void update_info () {
        var info = (machine.info != null && machine.info != "")? "<small>" + machine.info + "</small>": "";
        info_label.label = info;

        info_label.visible = (info != "");
    }

    private void update_status () {
        if (machine is RemoteMachine)
            update_status_label_style (!machine.is_connected);
        else
            update_status_label_style (!machine.is_on);

        if (machine.status != null) {
            status_label.label = machine.status;

            return;
        }

        if (machine is RemoteMachine) {
            status_label.label = machine.is_connected ? _("Connected"): _("Disconnected");

            return;
        }

        if (machine.is_running) {
            status_label.label = _("Running");

            return;
        }

        if (machine.is_on) {
            status_label.label = _("Paused");

            return;
        }

        status_label.label = _("Powered Off");
    }

    private void update_status_label_style (bool dim) {
        if (dim)
            status_label.get_style_context ().add_class ("dim-label");
        else
            status_label.get_style_context ().remove_class ("dim-label");
    }
}
