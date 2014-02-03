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

    public Gtk.Widget screenshot_placeholder;
    private GtkClutter.Actor gtk_actor;
    private Gtk.Notebook notebook;
    private Gtk.ListStore listmodel;
    private Gtk.TreeModelFilter model_filter;
    private Gtk.TreeView tree_view;
    private Gtk.Button shutdown_button;
    private MiniGraph cpu;
    private MiniGraph io;
    private MiniGraph net;
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
        listmodel.clear ();
        for (var i = 0; i < PropertiesPage.LAST; i++)
            notebook.remove_page (-1);

        var machine = App.app.current_item as Machine;
        var libvirt_machine = App.app.current_item as LibvirtMachine;

        shutdown_button.sensitive = libvirt_machine != null && libvirt_machine.is_running ();

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
                tree_view.get_selection ().select_path (path);
                notebook.page = current_page;
            });

            list_append (listmodel, page.name, !page.empty);
        }

        PropertiesPage current_page;

        if (libvirt_machine != null)
            current_page = (previous_ui_state == UIState.WIZARD) ? PropertiesPage.SYSTEM : PropertiesPage.LOGIN;
        else
            current_page = PropertiesPage.LOGIN;

        var path = new Gtk.TreePath.from_indices (current_page);
        tree_view.get_selection ().select_path (path);
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

        /* sidebar */
        var vbox = App.app.sidebar.get_nth_page (Boxes.SidebarPage.PROPERTIES) as Gtk.Box;

        tree_view = new Gtk.TreeView ();
        tree_view.get_style_context ().add_class ("boxes-bg");
        var selection = tree_view.get_selection ();
        selection.set_mode (Gtk.SelectionMode.BROWSE);
        tree_view.activate_on_single_click = true;
        tree_view.row_activated.connect ( (treeview, path, column) => {
            Gtk.TreeIter filter_iter, iter;
            model_filter.get_iter (out filter_iter, path);
            model_filter.convert_iter_to_child_iter (out iter, filter_iter);
            notebook.page = listmodel.get_path (iter).get_indices ()[0];
        });

        listmodel = new Gtk.ListStore (2, typeof (string), typeof (bool));
        model_filter = new Gtk.TreeModelFilter (listmodel, null);
        model_filter.set_visible_column (1);

        tree_view.set_model (model_filter);
        tree_view.headers_visible = false;
        var renderer = new CellRendererText ();
        renderer.xpad = 20;
        renderer.weight = Pango.Weight.BOLD;
        tree_view.insert_column_with_attributes (-1, "", renderer, "text", 0);
        vbox.pack_start (tree_view, true, true, 0);

        var grid = new Gtk.Grid ();
        vbox.pack_start (grid, false, false, 0);
        grid.column_homogeneous = false;
        grid.column_spacing = 2;
        grid.row_spacing = 10;
        grid.margin_left = 10;
        grid.margin_right = 10;
        grid.margin_bottom = 30;
        grid.margin_top = 10;

        screenshot_placeholder = new Gtk.Alignment (0.0f, 0.0f, 0.0f, 0.0f);
        screenshot_placeholder.set_size_request (180, 130);
        grid.attach (screenshot_placeholder, 0, 0, 6, 1);

        var label = new Gtk.Label (_("CPU:"));
        label.get_style_context ().add_class ("boxes-graph-label");
        grid.attach (label, 0, 1, 1, 1);
        cpu = new MiniGraph.with_ymax (100.0, 20);
        grid.attach (cpu, 1, 1, 1, 1);

        label = new Gtk.Label (_("I/O:"));
        label.get_style_context ().add_class ("boxes-graph-label");
        grid.attach (label, 2, 1, 1, 1);
        io = new MiniGraph (20);
        grid.attach (io, 3, 1, 1, 1);

        label = new Gtk.Label (_("Net:"));
        label.get_style_context ().add_class ("boxes-graph-label");
        grid.attach (label, 4, 1, 1, 1);
        net = new MiniGraph (20);
        grid.attach (net, 5, 1, 1, 1);

        shutdown_button = new Button.with_label (_("Force Shutdown"));
        shutdown_button.clicked.connect ( () => {
            var machine = App.app.current_item as LibvirtMachine;
            if (machine != null)
                machine.force_shutdown ();
        });
        grid.attach (shutdown_button, 0, 2, 6, 1);

        vbox.show_all ();
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
                    cpu.points = libvirt_machine.cpu_stats;
                    net.points = libvirt_machine.net_stats;
                    io.points = libvirt_machine.io_stats;
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
