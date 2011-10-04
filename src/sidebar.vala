using Gtk;
using Gdk;
using Clutter;
using GLib;

class Boxes.Sidebar: Boxes.UI {
    public Notebook notebook;
    public TreeView tree_view;

    private App app;
    private uint width;

    private Clutter.Actor actor; // the sidebar box

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
        this.width = 180;

        this.setup_sidebar ();
    }

    public override void ui_state_changed () {
        if (ui_state == UIState.DISPLAY)
            pin_actor(this.actor);
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
        this.notebook = new Gtk.Notebook ();
        this.notebook.set_size_request ((int)this.width, 100);

        var vbox = new Gtk.VBox (false, 0);
        this.notebook.append_page (vbox, new Gtk.Label (""));

        this.tree_view = new Gtk.TreeView ();
        var selection = this.tree_view.get_selection ();
        selection.set_select_function (selection_func);
        tree_view_activate_on_single_click (this.tree_view, true);
        this.tree_view.row_activated.connect ( (treeview, path, column) => {
            Gtk.TreeIter iter;
            Category category;
            var model = treeview.get_model ();
            bool selectable;

            model.get_iter (out iter, path);
            model.get (iter, 4, out category);
            model.get (iter, 2, out selectable);

            if (selectable)
                this.app.set_category (category);
        });

        vbox.pack_start (this.tree_view, true, true, 0);
        this.notebook.page = 0;
        this.notebook.show_tabs = false;
        this.notebook.show_all ();

        this.actor = new GtkClutter.Actor.with_contents (this.notebook);
        app.box.pack (this.actor, "column", 0, "row", 1, "x-expand", false, "y-expand", true);

        var listmodel = new ListStore (5,
                                       typeof (string),
                                       typeof (uint),
                                       typeof (bool),
                                       typeof (string),
                                       typeof (Category));
        this.tree_view.set_model (listmodel);
        this.tree_view.headers_visible = false;
        var pixbuf_renderer = new CellRendererPixbuf ();
        // pixbuf_renderer.width = 20;
        // pixbuf_renderer.mode = CellRendererMode.INERT;
        // pixbuf_renderer.xalign = 1f;
        pixbuf_renderer.xpad = 5;
        this.tree_view.insert_column_with_attributes (-1, "", pixbuf_renderer, "icon-name", 3);
        var renderer = new CellRendererText ();
        this.tree_view.insert_column_with_attributes (-1, "", renderer, "text", 0, "height", 1, "sensitive", 2);

        this.list_append (listmodel, new Category ("New and Recent"));
        selection.select_path (new Gtk.TreePath.from_string ("0"));
        this.list_append (listmodel, new Category ("Favorites"), "emblem-favorite-symbolic");
        this.list_append (listmodel, new Category ("Private"), "channel-secure-symbolic");
        this.list_append (listmodel, new Category ("Shared with you"), "emblem-shared-symbolic");
        this.list_append (listmodel, new Category ("Collections"), null, 40, false);
        // TODO: make it dynamic
        this.list_append (listmodel, new Category ("Work"));
        this.list_append (listmodel, new Category ("Game"));

        var create = new Gtk.Button.with_label ("Create");
        create.margin = 5;
        vbox.pack_end (create, false, false, 0);
        create.show ();

        this.app.state.set_key (null,
                                "display",
                                this.actor,
                                "x", AnimationMode.EASE_OUT_QUAD,
                                -(float) this.width,
                                0,
                                0); // FIXME: make it dynamic depending on sidebar size..
    }
}
