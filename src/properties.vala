// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private enum Boxes.PropertiesPage {
    LOGIN,
    SYSTEM,
    DISPLAY,
    DEVICES,

    LAST,
}

private class Boxes.Properties: Gtk.Notebook, Boxes.UI {
    public Clutter.Actor actor { get { return gtk_actor; } }
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private GtkClutter.Actor gtk_actor;
    private ulong stats_id;
    private bool restore_fullscreen;

    private class PageWidget: Gtk.Grid {
        public bool empty;

        private List<Boxes.Property> properties;

        public signal void refresh_properties ();

        public PageWidget (PropertiesPage page, Machine machine) {
            switch (page) {
            case PropertiesPage.LOGIN:
                name = _("Login");
                break;

            case PropertiesPage.SYSTEM:
                name = _("System");
                break;

            case PropertiesPage.DISPLAY:
                name = _("Display");
                break;

            case PropertiesPage.DEVICES:
                name = _("Devices");
                break;
            }

            margin = 20;
            row_spacing = 10;
            column_spacing = 20;
            valign = Gtk.Align.START;

            PropertyCreationFlag flags = PropertyCreationFlag.NONE;
            properties = machine.get_properties (page, ref flags);
            empty = properties.length () == 0;
            if (!empty) {
                int current_row = 1;
                foreach (var property in properties) {
                    if (property.description != null) {
                        var label_name = new Gtk.Label (property.description);
                        label_name.get_style_context ().add_class ("boxes-property-name-label");
                        label_name.margin_left = 25;
                        label_name.halign = Gtk.Align.START;
                        label_name.hexpand = false;
                        attach (label_name, 0, current_row, 1, 1);
                        var widget = property.widget;
                        widget.hexpand = true;
                        attach (widget, 1, current_row, 1, 1);
                    } else {
                        var widget = property.widget;
                        widget.hexpand = true;
                        widget.margin_left = 25;
                        attach (widget, 0, current_row, 2, 1);
                    }

                    var widget = property.extra_widget;
                    if (widget != null) {
                        current_row += 1;
                        widget.margin_left = 25;
                        widget.hexpand = true;
                        attach (widget, 0, current_row, 2, 1);
                    }

                    property.refresh_properties.connect (() => {
                        this.refresh_properties ();
                     });
                    current_row += 1;
                }
            }

            show_all ();
        }

        public bool flush_changes () {
            var reboot_required = false;

            foreach (var property in properties) {
                property.flush ();
                reboot_required |= property.reboot_required;
            }

            return reboot_required;
        }
    }

    public Properties () {
        notify["ui-state"].connect (ui_state_changed);
        setup_ui ();
    }

    private void list_append (Gtk.ListStore listmodel, string label, bool visible) {
        Gtk.TreeIter iter;

        listmodel.append (out iter);
        listmodel.set (iter, 0, label);
        listmodel.set (iter, 1, visible);
    }

    private void populate () {
        App.app.sidebar.props_listmodel.clear ();
        for (var i = 0; i < PropertiesPage.LAST; i++)
            remove_page (-1);

        var machine = App.app.current_item as Machine;
        var libvirt_machine = App.app.current_item as LibvirtMachine;

        App.app.sidebar.shutdown_button.sensitive = libvirt_machine != null && libvirt_machine.is_running ();

        if (machine == null)
            return;

        for (var i = 0; i < PropertiesPage.LAST; i++) {
            var page = new PageWidget (i, machine);
            append_page (page, null);
            set_data<PageWidget> (@"boxes-property-$i", page);

            page.refresh_properties.connect (() => {
                var current_page = page;
                this.populate ();
                var path = new Gtk.TreePath.from_indices (current_page);
                App.app.sidebar.props_selection.select_path (path);
                page = current_page;
            });

            list_append (App.app.sidebar.props_listmodel, page.name, !page.empty);
        }

        PropertiesPage current_page;

        if (libvirt_machine != null)
            current_page = (previous_ui_state == UIState.WIZARD) ? PropertiesPage.SYSTEM : PropertiesPage.LOGIN;
        else
            current_page = PropertiesPage.LOGIN;

        var path = new Gtk.TreePath.from_indices (current_page);
        App.app.sidebar.props_selection.select_path (path);
        set_current_page (current_page);
    }

    private void setup_ui () {
        show_tabs = false;
        get_style_context ().add_class ("boxes-bg");

        gtk_actor = new GtkClutter.Actor.with_contents (this);
        gtk_actor.get_widget ().get_style_context ().add_class ("boxes-bg");
        gtk_actor.name = "properties";
        gtk_actor.opacity = 0;
        gtk_actor.x_align = Clutter.ActorAlign.FILL;
        gtk_actor.y_align = Clutter.ActorAlign.FILL;
        gtk_actor.x_expand = true;
        gtk_actor.y_expand = true;

        show_all ();
    }

    private void ui_state_changed () {
        if (stats_id != 0) {
            App.app.current_item.disconnect (stats_id);
            stats_id = 0;
        }

        if (ui_state == UIState.PROPERTIES) {
            restore_fullscreen = (previous_ui_state == UIState.DISPLAY && App.app.fullscreen);
            App.app.fullscreen = false;

            if (App.app.current_item is LibvirtMachine) {
                var libvirt_machine = App.app.current_item as LibvirtMachine;
                stats_id = libvirt_machine.stats_updated.connect (() => {
                    App.app.sidebar.cpu_graph.points = libvirt_machine.cpu_stats;
                    App.app.sidebar.net_graph.points = libvirt_machine.net_stats;
                    App.app.sidebar.io_graph.points = libvirt_machine.io_stats;
                });
            }

            populate ();
        } else if (previous_ui_state == UIState.PROPERTIES) {
            var reboot_required = false;

            for (var i = 0; i < PropertiesPage.LAST; i++) {
                var page = get_data<PageWidget> (@"boxes-property-$i");
                reboot_required |= page.flush_changes ();
            }

            var machine = App.app.current_item as Machine;
            if (reboot_required && (machine.is_on () || machine.state == Machine.MachineState.SAVED)) {
                var message = _("Changes require restart of '%s'. Attempt restart?").printf (machine.name);
                App.app.notificationbar.display_for_action (message, _("_Yes"), () => {
                    machine.restart ();
                });
            }

            if (restore_fullscreen) {
                App.app.fullscreen = true;
                restore_fullscreen = false;
            }
        }

        fade_actor (actor, ui_state == UIState.PROPERTIES ? 255 : 0);
    }
}
