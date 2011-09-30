using Gtk;

public void tree_view_activate_on_single_click (Gtk.TreeView tv, bool should_activate)
{
	var id = tv.get_data<ulong> ("boxes-tree-view-activate");

	if (id != 0 && should_activate == false) {
		tv.disconnect (id);
		tv.set_data<ulong> ("boxes-tree-view-activate", 0);
	} else {
		id = tv.button_press_event.connect (
			(w, event) => {
				Gtk.TreePath? path;
				unowned Gtk.TreeViewColumn? column;
				int x, y;

				if (event.button == 1 && event.type == Gdk.EventType.BUTTON_PRESS) {
					tv.get_path_at_pos ((int)event.x, (int)event.y, out path, out column, out x, out y);
					tv.row_activated (path, column);
				}
				return false;
			});
		tv.set_data<ulong> ("boxes-tree-view-activate", id);
	}
}

