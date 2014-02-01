// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private enum Boxes.PropertiesPage {
    LOGIN,
    SYSTEM,
    DISPLAY,
    DEVICES,

    LAST,
}

private class Boxes.Properties: GLib.Object, Boxes.UI {
    public Clutter.Actor actor { get { return gtk_actor; } }
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private GtkClutter.Actor gtk_actor;
    public Gtk.Notebook notebook;
    private ulong stats_id;
    private bool restore_fullscreen;

    private class PageWidget: Object {
        public Gtk.Widget widget;
        public string name;
        public bool empty;

        private Gtk.Grid grid;
        private Gtk.InfoBar infobar;
        private List<Boxes.Property> properties;

        public signal void refresh_properties ();

        public void update_infobar () {
            var show_it = false;
            foreach (var property in properties) {
                if (property.reboot_required) {
                    show_it = true;
                    break;
                }
            }
            infobar.visible = show_it;
        }

        ~PageWidget () {
            foreach (var property in properties) {
                SignalHandler.disconnect_by_func (property, (void*)update_infobar, this);
            }
        }

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

            grid = new Gtk.Grid ();
            grid.margin = 20;
            grid.row_spacing = 10;
            grid.column_spacing = 20;
            grid.valign = Gtk.Align.START;

            infobar = new Gtk.InfoBar ();
            infobar.no_show_all = true;
            var infobar_container = infobar.get_content_area () as Gtk.Container;
            var label = new Gtk.Label (_("Some changes may take effect only after reboot"));
            label.visible = true;
            infobar_container.add (label);
            infobar.message_type = Gtk.MessageType.INFO;
            infobar.hexpand = true;
            grid.attach (infobar, 0, 0, 2, 1);

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
                        grid.attach (label_name, 0, current_row, 1, 1);
                        var widget = property.widget;
                        widget.hexpand = true;
                        grid.attach (widget, 1, current_row, 1, 1);
                    } else {
                        var widget = property.widget;
                        widget.hexpand = true;
                        widget.margin_left = 25;
                        grid.attach (widget, 0, current_row, 2, 1);
                    }

                    widget = property.extra_widget;
                    if (widget != null) {
                        current_row += 1;
                        widget.margin_left = 25;
                        widget.hexpand = true;
                        grid.attach (widget, 0, current_row, 2, 1);
                    }

                    property.notify["reboot-required"].connect (update_infobar);
                    property.refresh_properties.connect (() => {
                        this.refresh_properties ();
                     });
                    current_row += 1;
                }

                update_infobar ();
            }

            grid.show_all ();
            widget = grid;
        }

        public void flush_changes () {
            foreach (var property in properties)
                property.flush ();
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
            notebook.remove_page (-1);

        var machine = App.app.current_item as Machine;
        var libvirt_machine = App.app.current_item as LibvirtMachine;

        App.app.sidebar.shutdown_button.sensitive = libvirt_machine != null && libvirt_machine.is_running ();

        if (machine == null)
            return;

        for (var i = 0; i < PropertiesPage.LAST; i++) {
            var page = new PageWidget (i, machine);
            notebook.append_page (page.widget, null);
            notebook.set_data<PageWidget> (@"boxes-property-$i", page);

            page.refresh_properties.connect (() => {
                var current_page = notebook.page;
                this.populate ();
                var path = new Gtk.TreePath.from_indices (current_page);
                App.app.sidebar.props_selection.select_path (path);
                notebook.page = current_page;
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
        notebook.set_current_page (current_page);
    }

    private void setup_ui () {
        notebook = new Gtk.Notebook ();
        notebook.show_tabs = false;
        notebook.get_style_context ().add_class ("boxes-bg");
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);
        gtk_actor.get_widget ().get_style_context ().add_class ("boxes-bg");
        gtk_actor.name = "properties";
        gtk_actor.opacity = 0;
        gtk_actor.x_align = Clutter.ActorAlign.FILL;
        gtk_actor.y_align = Clutter.ActorAlign.FILL;
        gtk_actor.x_expand = true;
        gtk_actor.y_expand = true;

        notebook.show_all ();
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
            for (var i = 0; i < PropertiesPage.LAST; i++) {
                var page = notebook.get_data<PageWidget> (@"boxes-property-$i");
                page.flush_changes ();
            }

            if (restore_fullscreen) {
                App.app.fullscreen = true;
                restore_fullscreen = false;
            }
        }

        fade_actor (actor, ui_state == UIState.PROPERTIES ? 255 : 0);
    }
}
