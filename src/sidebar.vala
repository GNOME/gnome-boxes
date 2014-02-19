// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;
using Clutter;

private enum Boxes.SidebarPage {
    COLLECTION,
    WIZARD,
    PROPERTIES,
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/sidebar.ui")]
private class Boxes.Sidebar: Gtk.Revealer, Boxes.UI {
    // See FIXME on Topbar class
    public Clutter.Actor actor {
        get {
            if (gtk_actor == null)
                gtk_actor = new Clutter.Actor ();
            return gtk_actor;
        }
    }
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private Clutter.Actor gtk_actor; // the sidebar box

    [GtkChild]
    private Gtk.Notebook notebook;
    [GtkChild]
    private Gtk.Box wizard_vbox;
    [GtkChild]
    private Gtk.Label wizard_intro_label;
    [GtkChild]
    private Gtk.Label wizard_source_label;
    [GtkChild]
    private Gtk.Label wizard_preparation_label;
    [GtkChild]
    private Gtk.Label wizard_setup_label;
    [GtkChild]
    private Gtk.Label wizard_review_label;

    [GtkChild]
    public Gtk.Image screenshot;
    [GtkChild]
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

    public Sidebar () {
        notify["ui-state"].connect (ui_state_changed);
        setup_sidebar ();
    }

    public void set_wizard_page (WizardPage wizard_page) {
        foreach (var label in wizard_vbox.get_children ())
            label.get_style_context ().remove_class ("boxes-wizard-current-page-label");

        Gtk.Label current_label = null;
        switch ((int) wizard_page) {
        case WizardPage.INTRODUCTION:
            current_label = wizard_intro_label;
            break;
        case WizardPage.SOURCE:
            current_label = wizard_source_label;
            break;
        case WizardPage.PREPARATION:
            current_label = wizard_preparation_label;
            break;
        case WizardPage.SETUP:
            current_label = wizard_setup_label;
            break;
        case WizardPage.REVIEW:
            current_label = wizard_review_label;
            break;
        }
        current_label.get_style_context ().add_class ("boxes-wizard-current-page-label");
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
        App.app.properties.page = props_listmodel.get_path (iter).get_indices ()[0];
    }

    [GtkCallback]
    private void on_shutdown_button_clicked () {
        var machine = App.app.current_item as LibvirtMachine;
        if (machine != null)
            machine.force_shutdown ();
    }
}
