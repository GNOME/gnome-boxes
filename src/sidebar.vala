using Gtk;
using Gdk;
using Clutter;
using GLib;

class Sidebar: BoxesUI {
    Boxes boxes;
    uint width = 200;

    Clutter.Actor actor; // the sidebar box
    public Gtk.Notebook notebook;
    public Gtk.TreeView tree_view;

    public Sidebar(Boxes boxes) {
        this.boxes = boxes;
        setup_sidebar ();
    }

    private void list_append (ListStore listmodel,
							  Category category,
							  string? icon = null,
							  uint height = 0,
							  bool sensitive = true) {
        Gtk.TreeIter iter;

        listmodel.append (out iter);
        listmodel.set (iter, 0, category.name);
        listmodel.set (iter, 1, height);
        listmodel.set (iter, 2, sensitive);
        listmodel.set (iter, 3, icon);
		listmodel.set (iter, 4, category);
    }

    private static bool selection_func (Gtk.TreeSelection selection, Gtk.TreeModel model,
                                        Gtk.TreePath path, bool path_currently_selected) {
        Gtk.TreeIter iter;
        bool selectable;

        model.get_iter (out iter, path);
        model.get (iter, 2, out selectable);
        return selectable;
    }

    private void setup_sidebar () {
        notebook = new Gtk.Notebook ();
        notebook.set_size_request ((int)width, 200);

        var vbox = new Gtk.VBox (false, 0);
        notebook.append_page (vbox, new Gtk.Label (""));

        tree_view = new Gtk.TreeView ();
        var selection = tree_view.get_selection ();
        selection.set_select_function (selection_func);
        tree_view_activate_on_single_click (tree_view, true);
		tree_view.row_activated.connect ( (tv, path, column) => {
				Gtk.TreeIter iter;
				Category category;
				var model = tv.get_model ();
				bool selectable;

				model.get_iter (out iter, path);
				model.get (iter, 4, out category);
				model.get (iter, 2, out selectable);

				if (selectable)
					boxes.set_category (category);
			});

        vbox.pack_start (tree_view, true, true, 0);
        notebook.page = 0;
        notebook.show_tabs = false;
        notebook.show_all ();

        actor = new GtkClutter.Actor.with_contents (notebook);
        boxes.cbox.pack (actor, "column", 0, "row", 1, "x-expand", false, "y-expand", true);

        var listmodel = new ListStore (5, typeof (string), typeof (uint), typeof (bool), typeof (string), typeof (Category));
        tree_view.set_model (listmodel);
        tree_view.headers_visible = false;
        tree_view.insert_column_with_attributes (-1, "", new CellRendererPixbuf (), "icon-name", 3);
        tree_view.insert_column_with_attributes (-1, "", new CellRendererText (), "text", 0, "height", 1, "sensitive", 2);

        list_append (listmodel, new Category ("New and Recent"));
        selection.select_path (new Gtk.TreePath.from_string ("0"));
        list_append (listmodel, new Category ("Favorites"), "emblem-favorite-symbolic");
        list_append (listmodel, new Category ("Private"), "channel-secure-symbolic");
        list_append (listmodel, new Category ("Shared with you"), "emblem-shared-symbolic");
        list_append (listmodel, new Category ("Collections"), null, 40, false);
        list_append (listmodel, new Category ("Work"));
        list_append (listmodel, new Category ("Game"));

        var create = new Gtk.Button.with_label ("Create");
        vbox.pack_end (create, false, false, 0);
        create.show ();

        boxes.cstate.set_key (null, "remote", actor, "x", AnimationMode.EASE_OUT_QUAD, -(float)width, 0, 0); // FIXME: make it dynamic depending on sidebar size..
    }

    public override void ui_state_changed () {
        if (ui_state == UIState.REMOTE) {
            pin_actor(actor);
        }
    }
}
