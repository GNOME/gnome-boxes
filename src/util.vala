using GLib;
using Gtk;
using Config;

public string get_pkgdata (string? file = null) {
    return Path.build_filename (Config.DATADIR, Config.PACKAGE_TARNAME, file);
}

public string get_style (string? file = null) {
    return Path.build_filename (get_pkgdata (), "style", file);
}

public string get_pkgcache (string? file = null) {
	var dir = Path.build_filename (Environment.get_user_cache_dir (), Config.PACKAGE_TARNAME);

	try {
		var f = GLib.File.new_for_path (dir);
		f.make_directory_with_parents (null);
	} catch (GLib.Error e) {
		if (!(e is IOError.EXISTS))
			warning (e.message);
	}

	return Path.build_filename (dir, file);
}

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

public async void output_stream_write (OutputStream o, uint8[] buffer) throws GLib.IOError
{
	var l = buffer.length;
	ssize_t i = 0;

	while (i < l) {
		i += yield o.write_async (buffer[i:l]);
		message (i.to_string ());
	}
}
