// This file is part of GNOME Boxes. License: LGPLv2+

using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/icon-view-child.ui")]
private class Boxes.IconViewChild : Gtk.Box {
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
    private unowned Gtk.Spinner spinner;
    [GtkChild]
    private unowned Gtk.Image favorite;
    [GtkChild]
    private unowned Gtk.Image live_thumbnail;
    [GtkChild]
    private unowned Gtk.Label machine_name;

    private Boxes.MachineThumbnailer thumbnailer;

    private Binding selected_binding;


    public IconViewChild (CollectionItem item) {
        this.item = item;

        thumbnailer = machine.thumbnailer;

        thumbnailer.favorite_emblem_enabled = false;
        thumbnailer.notify["thumbnail"].connect (() => {
            thumbnail.set_from_pixbuf (thumbnailer.thumbnail);
        });
        thumbnail.set_from_pixbuf (thumbnailer.thumbnail);

        selected_binding = bind_property ("selected", selection_button, "active", BindingFlags.BIDIRECTIONAL);

        machine.config.notify["categories"].connect (update_favorite);
        machine.notify["under-construction"].connect (update_thumbnail);

        update_thumbnail ();
        update_favorite ();

        machine.bind_property ("name", machine_name, "label", BindingFlags.SYNC_CREATE);
    }

    private void update_thumbnail () {
        var libvirt_machine = machine as LibvirtMachine;

        if (machine.under_construction) {
            stack.visible_child = spinner;
            spinner.start ();
            spinner.visible = true;

            return;
        } else if (VMConfigurator.is_live_config (libvirt_machine.domain_config)) {
            stack.visible_child = live_thumbnail;
        } else {
            stack.visible_child = thumbnail;
        }

        spinner.stop ();
    }

    private void update_favorite () {
        if ("favorite" in machine.config.categories)
            favorite.set_from_icon_name ("starred-symbolic", Gtk.IconSize.MENU);
        else
            favorite.clear ();
    }
}
