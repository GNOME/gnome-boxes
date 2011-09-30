using Gtk;
using Gdk;
using Clutter;
using GLib;

class Sidebar: BoxesUI {
	Boxes boxes;
    uint width = 200;

    Clutter.Actor actor; // the sidebar box
    public Gtk.Notebook notebook;

	public Sidebar(Boxes boxes) {
		this.boxes = boxes;
		setup_sidebar ();
	}

	private void list_append (ListStore listmodel, string name, string? icon = null, uint height = 0, bool sensitive = true) {
        Gtk.TreeIter iter;

        listmodel.append (out iter);
        listmodel.set (iter, 0, name);
        listmodel.set (iter, 1, height);
        listmodel.set (iter, 2, sensitive);
        listmodel.set (iter, 3, icon);
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

        var view = new Gtk.TreeView ();
        var selection = view.get_selection ();
        selection.set_select_function (selection_func);
        tree_view_activate_on_single_click (view, true);
        notebook.append_page (view, new Gtk.Label ("foo"));
        notebook.page = 0;
        notebook.show_tabs = false;
        notebook.show_all ();

        actor = new GtkClutter.Actor.with_contents (notebook);
        boxes.cbox.pack (actor, "column", 0, "row", 1, "x-expand", false, "y-expand", true);

        var listmodel = new ListStore (4, typeof (string), typeof (uint), typeof (bool), typeof (string));
        view.set_model (listmodel);
        view.headers_visible = false;
        view.insert_column_with_attributes (-1, "", new CellRendererPixbuf (), "icon-name", 3);
        view.insert_column_with_attributes (-1, "", new CellRendererText (), "text", 0, "height", 1, "sensitive", 2);

        list_append (listmodel, "New and Recent");
        selection.select_path (new Gtk.TreePath.from_string ("0"));
        list_append (listmodel, "Favorites", "emblem-favorite-symbolic");
        list_append (listmodel, "Private", "channel-secure-symbolic");
        list_append (listmodel, "Shared with you", "emblem-shared-symbolic");
        list_append (listmodel, "Collections", null, 40, false);
        list_append (listmodel, "Work");
        list_append (listmodel, "Game");

        boxes.cstate.set_key (null, "remote", actor, "x", AnimationMode.EASE_OUT_QUAD, -(float)width, 0, 0); // FIXME: make it dynamic depending on sidebar size..
    }

	public override void ui_state_changed () {
        if (ui_state == UIState.REMOTE) {
			pin_actor(actor);
		}
	}
}
