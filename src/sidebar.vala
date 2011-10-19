// This file is part of GNOME Boxes. License: LGPLv2
using Gtk;
using Gdk;
using Clutter;

private enum Boxes.SidebarPage {
    COLLECTION,
    WIZARD,
}

private class Boxes.Sidebar: Boxes.UI {
    public override Clutter.Actor actor { get { return gtk_actor; } }
    public Notebook notebook;
    public TreeView tree_view;

    private App app;
    private uint width;

    private GtkClutter.Actor gtk_actor; // the sidebar box

    private bool selection_func (Gtk.TreeSelection selection,
                                 Gtk.TreeModel     model,
                                 Gtk.TreePath      path,
                                 bool              path_currently_selected) {
        Gtk.TreeIter iter;
        bool selectable;

        model.get_iter (out iter, path);
        model.get (iter, 2, out selectable);

        return selectable;
    }

    public Sidebar (App app) {
        this.app = app;
        width = 180;

        setup_sidebar ();
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.COLLECTION:
            notebook.page = SidebarPage.COLLECTION;
            break;
        case UIState.DISPLAY:
            actor_pin (actor);
            break;
        case UIState.WIZARD:
            notebook.page = SidebarPage.WIZARD;
            break;
        }
    }

    private void list_append (ListStore listmodel,
                              Category  category,
                              string?   icon = null,
                              uint      height = 0,
                              bool      sensitive = true) {
        Gtk.TreeIter iter;

        listmodel.append (out iter);
        listmodel.set (iter, 0, category.name);
        listmodel.set (iter, 1, height);
        listmodel.set (iter, 2, sensitive);
        listmodel.set (iter, 3, icon);
        listmodel.set (iter, 4, category);
    }

    private void setup_sidebar () {
        notebook = new Gtk.Notebook ();
        notebook.get_style_context ().add_class ("boxes-sidebar-bg");
        notebook.set_size_request ((int) width, 100);

        /* SidebarPage.COLLECTION */
        var vbox = new Gtk.VBox (false, 0);
        notebook.append_page (vbox, null);

        tree_view = new Gtk.TreeView ();
        var selection = tree_view.get_selection ();
        selection.set_select_function (selection_func);
        tree_view_activate_on_single_click (tree_view, true);
        tree_view.row_activated.connect ( (treeview, path, column) => {
            Gtk.TreeIter iter;
            Category category;
            var model = treeview.get_model ();
            bool selectable;

            model.get_iter (out iter, path);
            model.get (iter, 4, out category);
            model.get (iter, 2, out selectable);

            if (selectable)
                app.set_category (category);
        });

        vbox.pack_start (tree_view, true, true, 0);
        notebook.show_tabs = false;

        gtk_actor = new GtkClutter.Actor.with_contents (notebook);
        app.box.pack (gtk_actor, "column", 0, "row", 1, "x-expand", false, "y-expand", true);

        var listmodel = new ListStore (5,
                                       typeof (string),
                                       typeof (uint),
                                       typeof (bool),
                                       typeof (string),
                                       typeof (Category));
        tree_view.set_model (listmodel);
        tree_view.headers_visible = false;
        var pixbuf_renderer = new CellRendererPixbuf ();
        // pixbuf_renderer.width = 20;
        // pixbuf_renderer.mode = CellRendererMode.INERT;
        // pixbuf_renderer.xalign = 1f;
        pixbuf_renderer.xpad = 5;
        tree_view.insert_column_with_attributes (-1, "", pixbuf_renderer, "icon-name", 3);
        var renderer = new CellRendererText ();
        tree_view.insert_column_with_attributes (-1, "", renderer, "text", 0, "height", 1, "sensitive", 2);

        list_append (listmodel, new Category (_("New and Recent")));
        selection.select_path (new Gtk.TreePath.from_string ("0"));
        list_append (listmodel, new Category (_("Favorites")), "emblem-favorite-symbolic");
        list_append (listmodel, new Category (_("Private")), "channel-secure-symbolic");
        list_append (listmodel, new Category (_("Shared with you")), "emblem-shared-symbolic");
        list_append (listmodel, new Category (_("Collections")), null, 40, false);
        // TODO: make it dynamic
        list_append (listmodel, new Category (_("Work")));
        list_append (listmodel, new Category (_("Game")));

        var create = new Gtk.Button.with_label (_("Create"));
        create.margin = 5;
        vbox.pack_end (create, false, false, 0);
        create.show ();
        create.clicked.connect (() => {
            app.go_create ();
        });

        /* SidebarPage.WIZARD */
        vbox = new Gtk.VBox (false, 0);
        notebook.append_page (vbox, null);

        notebook.show_all ();

        // FIXME: make it dynamic depending on sidebar size..:
        app.state.set_key (null, "display", gtk_actor, "x", AnimationMode.EASE_OUT_QUAD, -(float) width, 0, 0);
    }
}
