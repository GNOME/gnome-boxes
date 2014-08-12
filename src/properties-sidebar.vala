// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/properties-sidebar.ui")]
private class Boxes.PropertiesSidebar: Gtk.Box {
    [GtkChild]
    public Gtk.Image screenshot;
    [GtkChild]
    public Gtk.ListStore listmodel;
    [GtkChild]
    private Gtk.TreeModelFilter model_filter;
    [GtkChild]
    public Gtk.TreeSelection selection;
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
        model_filter.set_visible_column (1);
    }

    public void setup_ui (AppWindow window) {
        this.window = window;
    }

    [GtkCallback]
    private void on_row_activated (Gtk.TreeView treeview, Gtk.TreePath path, Gtk.TreeViewColumn column) {
        Gtk.TreeIter filter_iter, iter;
        model_filter.get_iter (out filter_iter, path);
        model_filter.convert_iter_to_child_iter (out iter, filter_iter);
        window.properties.page = (PropertiesPage) listmodel.get_path (iter).get_indices ()[0];
    }

    [GtkCallback]
    private void on_shutdown_button_clicked () {
        var machine = window.current_item as LibvirtMachine;
        if (machine != null)
            machine.force_shutdown ();
    }
}
