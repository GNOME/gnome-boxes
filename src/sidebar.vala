// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

private enum Boxes.SidebarPage {
    WIZARD,
    PROPERTIES,
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/sidebar.ui")]
private class Boxes.Sidebar: Gtk.Revealer, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    [GtkChild]
    public WizardSidebar wizard_sidebar;
    [GtkChild]
    public Gtk.Image screenshot;
    [GtkChild]
    private Gtk.Notebook notebook;
    public Gtk.ListStore props_listmodel;
    [GtkChild]
    private Gtk.TreeModelFilter props_model_filter;
    [GtkChild]
    public Gtk.TreeSelection props_selection;
    [GtkChild]
    public Gtk.Button shutdown_button;
    [GtkChild]
    public MiniGraph cpu_graph;
    [GtkChild]
    public MiniGraph io_graph;
    [GtkChild]
    public MiniGraph net_graph;

    private AppWindow window;

    construct {
        notify["ui-state"].connect (ui_state_changed);
        setup_sidebar ();
    }

    public void setup_ui (AppWindow window) {
        this.window = window;
    }

    private void ui_state_changed () {
        switch (ui_state) {
        case UIState.WIZARD:
        case UIState.PROPERTIES:
            reveal_child = true;
            notebook.page = ui_state == UIState.WIZARD ? SidebarPage.WIZARD : SidebarPage.PROPERTIES;
            break;

        default:
            reveal_child = false;
            break;
        }
    }

    private void setup_sidebar () {
        props_model_filter.set_visible_column (1);
    }

    [GtkCallback]
    private void on_props_row_activated (Gtk.TreeView treeview, Gtk.TreePath path, Gtk.TreeViewColumn column) {
        Gtk.TreeIter filter_iter, iter;
        props_model_filter.get_iter (out filter_iter, path);
        props_model_filter.convert_iter_to_child_iter (out iter, filter_iter);
        window.properties.page = (PropertiesPage) props_listmodel.get_path (iter).get_indices ()[0];
    }

    [GtkCallback]
    private void on_shutdown_button_clicked () {
        var machine = window.current_item as LibvirtMachine;
        if (machine != null)
            machine.force_shutdown ();
    }
}
