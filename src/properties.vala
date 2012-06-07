// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private enum Boxes.PropertiesPage {
    LOGIN,
    SYSTEM,
    DISPLAY,
    DEVICES,

    LAST,
}

private class Boxes.Properties: Boxes.UI {
    public override Clutter.Actor actor { get { return gtk_actor; } }

    public Gtk.Widget screenshot_placeholder;
    private GtkClutter.Actor gtk_actor;
    private Boxes.App app;
    private Gtk.Notebook notebook;
    private Gtk.ToolButton back;
    private Gtk.Label toolbar_label;
    private Gtk.ListStore listmodel;
    private Gtk.TreeView tree_view;
    private GLib.Binding toolbar_label_bind;
    private MiniGraph cpu;
    private MiniGraph io;
    private MiniGraph net;
    private ulong stats_id;

    private class PageWidget {
        public Gtk.Widget widget;
        public string name;
        public bool empty;

        private Gtk.Grid grid;

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

            var label = new Gtk.Label (name);
            label.get_style_context ().add_class ("boxes-step-label");
            label.margin_bottom = 10;
            label.xalign = 0.0f;
            label.hexpand = false;
            grid.attach (label, 0, 0, 2, 1);

            var properties = machine.get_properties (page);
            empty = properties.length () == 0;
            if (!empty) {
                int current_row = 1;
                foreach (var property in properties) {
                    var label_name = new Gtk.Label (property.first);
                    label_name.modify_fg (Gtk.StateType.NORMAL, get_color ("grey"));
                    label_name.margin_left = 25;
                    label_name.halign = Gtk.Align.START;
                    label_name.hexpand = false;
                    grid.attach (label_name, 0, current_row, 1, 1);
                    var widget = property.second;
                    grid.attach (widget, 1, current_row, 1, 1);

                    current_row += 1;
                }
            }

            grid.show_all ();
            widget = grid;
        }
    }

    public Properties (App app) {
        this.app = app;

        setup_ui ();
    }

    private void list_append (Gtk.ListStore listmodel, string label) {
        Gtk.TreeIter iter;

        listmodel.append (out iter);
        listmodel.set (iter, 0, label);
    }

    private void populate () {
        listmodel.clear ();
        for (var i = 0; i < PropertiesPage.LAST; i++)
            notebook.remove_page (-1);

        if (app.current_item == null)
            return;

        for (var i = 0; i < PropertiesPage.LAST; i++) {
            var machine = app.current_item as Machine;
            var page = new PageWidget (i, machine);
            notebook.append_page (page.widget, null);

            if (!page.empty)
                list_append (listmodel, page.name);
        }

        tree_view.get_selection ().select_path (new Gtk.TreePath.from_string ("0"));

        var machine = app.current_item as LibvirtMachine;
        if (machine != null) {
            stats_id = machine.stats_updated.connect (() => {
                cpu.points = machine.cpu_stats;
                net.points = machine.net_stats;
                io.points = machine.io_stats;
            });
        }
    }

    private void setup_ui () {
        notebook = new Gtk.Notebook ();
        notebook.show_tabs = false;
        notebook.get_style_context ().add_class ("boxes-bg");
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);
        gtk_actor.name = "properties";
        gtk_actor.opacity = 0;

        /* topbar */
        var hbox = app.topbar.notebook.get_nth_page (Boxes.TopbarPage.PROPERTIES) as Gtk.HBox;

        var toolbar = new Toolbar ();
        toolbar.set_valign (Align.CENTER);
        toolbar.icon_size = IconSize.MENU;
        toolbar.get_style_context ().add_class (STYLE_CLASS_MENUBAR);
        toolbar.set_show_arrow (false);

        var toolbar_box = new Gtk.HBox (false, 0);
        toolbar_box.set_size_request (50, (int) Boxes.Topbar.height);
        toolbar_box.add (toolbar);

        var box = new Gtk.HBox (false, 5);
        box.add (new Gtk.Image.from_icon_name ("go-previous-symbolic", Gtk.IconSize.MENU));
        toolbar_label = new Gtk.Label ("label");
        box.add (toolbar_label);
        back = new ToolButton (box, null);
        back.get_style_context ().add_class ("raised");
        back.clicked.connect ((button) => { app.ui_state = UIState.DISPLAY; });
        toolbar.insert (back, 0);
        hbox.pack_start (toolbar_box, true, true, 0);

        hbox.show_all ();

        /* sidebar */
        var vbox = app.sidebar.notebook.get_nth_page (Boxes.SidebarPage.PROPERTIES) as Gtk.VBox;

        tree_view = new Gtk.TreeView ();
        var selection = tree_view.get_selection ();
        selection.set_mode (Gtk.SelectionMode.BROWSE);
        tree_view_activate_on_single_click (tree_view, true);
        tree_view.row_activated.connect ( (treeview, path, column) => {
            notebook.page = path.get_indices ()[0];
        });

        listmodel = new Gtk.ListStore (1, typeof (string));
        tree_view.set_model (listmodel);
        tree_view.headers_visible = false;
        var renderer = new CellRendererText ();
        renderer.xpad = 20;
        tree_view.insert_column_with_attributes (-1, "", renderer, "text", 0);
        vbox.pack_start (tree_view, true, true, 0);

        var grid = new Gtk.Grid ();
        vbox.pack_start (grid, false, false, 0);
        grid.column_homogeneous = true;
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
        cpu = new MiniGraph.with_ymax ({}, 100.0, 20);
        cpu.hexpand = true;
        grid.attach (cpu, 1, 1, 1, 1);

        label = new Gtk.Label (_("I/O:"));
        label.get_style_context ().add_class ("boxes-graph-label");
        grid.attach (label, 2, 1, 1, 1);
        io = new MiniGraph ({}, 20);
        io.hexpand = true;
        grid.attach (io, 3, 1, 1, 1);

        label = new Gtk.Label (_("Net:"));
        label.get_style_context ().add_class ("boxes-graph-label");
        grid.attach (label, 4, 1, 1, 1);
        net = new MiniGraph ({}, 20);
        net.hexpand = true;
        grid.attach (net, 5, 1, 1, 1);

        vbox.show_all ();
        notebook.show_all ();
    }

    public override void ui_state_changed () {
        uint opacity = 0;
        if (stats_id != 0) {
            app.current_item.disconnect (stats_id);
            stats_id = 0;
        }

        switch (ui_state) {
        case UIState.PROPERTIES:
            toolbar_label_bind = app.current_item.bind_property ("name", toolbar_label, "label", BindingFlags.SYNC_CREATE);
            populate ();
            opacity = 255;
            break;
        }
        fade_actor (actor, opacity);
    }
}
