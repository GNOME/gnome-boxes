// This file is part of GNOME Boxes. License: LGPLv2+

using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/icon-view-child.ui")]
private class Boxes.IconViewChild : Gtk.Box {
    public const int SCREENSHOT_WIDTH = 180;
    public const int SCREENSHOT_HEIGHT = 134;

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
    private unowned Gtk.CheckButton selection_button;
    [GtkChild]
    private unowned Gtk.Stack stack;
    [GtkChild]
    public unowned Gtk.Image thumbnail;
    [GtkChild]
    private unowned Gtk.EventBox spinner_box;
    [GtkChild]
    private unowned Gtk.Spinner spinner;
    [GtkChild]
    private unowned Gtk.Image favorite;
    [GtkChild]
    private unowned Gtk.Image running_thumbnail;
    [GtkChild]
    private unowned Gtk.Label machine_name;

    private Boxes.MachineThumbnailer thumbnailer;

    private Binding selected_binding;


    public IconViewChild (CollectionItem item) {
        this.item = item;

        thumbnailer = new MachineThumbnailer (machine,
                                              SCREENSHOT_WIDTH,
                                              SCREENSHOT_HEIGHT);

        stack.width_request = SCREENSHOT_WIDTH;
        stack.height_request = SCREENSHOT_HEIGHT;

        selected_binding = bind_property ("selected", selection_button, "active", BindingFlags.BIDIRECTIONAL);

        machine.config.notify["categories"].connect (update_favorite);
        machine.notify["under-construction"].connect (update_thumbnail);
        machine.notify["is-stopped"].connect (update_thumbnail);
        thumbnailer.notify["thumbnail"].connect (() => {
            update_thumbnail ();
            update_favorite ();
        });

        update_thumbnail ();
        update_favorite ();

        machine.bind_property ("name", machine_name, "label", BindingFlags.SYNC_CREATE);
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

    private void update_favorite () {
        favorite.visible = "favorite" in machine.config.categories;

        if (thumbnailer.thumbnail != null)
            favorite.get_style_context ().add_class ("running");
        else
            favorite.get_style_context ().remove_class ("running");
    }
}
