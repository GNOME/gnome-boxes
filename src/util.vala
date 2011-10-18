// This file is part of GNOME Boxes. License: LGPLv2
using Gtk;
using Config;
using Xml;

namespace Boxes {
    // FIXME: Remove these when we can use Vala release that provides binding for gdkkeysyms.h
    private const uint F10_KEY = 0xffc7;
    private const uint F11_KEY = 0xffc8;
    private const uint F12_KEY = 0xffc9;

    private string get_pkgdata (string? file_name = null) {
        return Path.build_filename (DATADIR, Config.PACKAGE_TARNAME, file_name);
    }

    private string get_style (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "style", file_name);
    }

    private string get_pixmap (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "pixmaps", file_name);
    }

    private string get_pkgcache (string? file_name = null) {
        var dir = Path.build_filename (Environment.get_user_cache_dir (), Config.PACKAGE_TARNAME);

        try {
            var file = GLib.File.new_for_path (dir);
            file.make_directory_with_parents (null);
        } catch (GLib.Error e) {
            if (!(e is IOError.EXISTS))
                warning (e.message);
        }

        return Path.build_filename (dir, file_name);
    }

    private Clutter.Color gdk_rgba_to_clutter_color (Gdk.RGBA gdk_rgba) {
        Clutter.Color color = {
            (uint8) (gdk_rgba.red * 255).clamp (0, 255),
            (uint8) (gdk_rgba.green * 255).clamp (0, 255),
            (uint8) (gdk_rgba.blue * 255).clamp (0, 255),
            (uint8) (gdk_rgba.alpha * 255).clamp (0, 255)
        };

        return color;
    }

    private Gdk.RGBA get_boxes_bg_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("boxes-bg");
        return style.get_background_color (0);
    }

    private Gdk.Color get_color (string desc) {
        Gdk.Color color;
        Gdk.Color.parse (desc, out color);
        return color;
    }

    private void tree_view_activate_on_single_click (Gtk.TreeView tree_view, bool should_activate) {
        var id = tree_view.get_data<ulong> ("boxes-tree-view-activate");

        if (id != 0 && should_activate == false) {
            tree_view.disconnect (id);
            tree_view.set_data<ulong> ("boxes-tree-view-activate", 0);
        } else {
            id = tree_view.button_press_event.connect ((w, event) => {
                Gtk.TreePath? path;
                unowned Gtk.TreeViewColumn? column;
                int x, y;

                if (event.button == 1 && event.type == Gdk.EventType.BUTTON_PRESS) {
                    tree_view.get_path_at_pos ((int) event.x, (int) event.y, out path, out column, out x, out y);
                    if (path != null)
                        tree_view.row_activated (path, column);
                }

                return false;
            });
            tree_view.set_data<ulong> ("boxes-tree-view-activate", id);
        }
    }

    private async void output_stream_write (OutputStream stream, uint8[] buffer) throws GLib.IOError {
        var length = buffer.length;
        ssize_t i = 0;

        while (i < length)
            i += yield stream.write_async (buffer[i:length]);
    }

    private string? extract_xpath (string xmldoc, string xpath, bool required = false) throws Boxes.Error {
        var parser = new ParserCtxt ();
        var doc = parser.read_doc (xmldoc, "doc.xml");

        if (doc == null)
            throw new Boxes.Error.INVALID ("Can't parse XML doc");

        var ctxt = new XPath.Context (doc);
        var obj = ctxt.eval (xpath);
        if (obj == null || obj->stringval == null) {
            if (required)
                throw new Boxes.Error.INVALID ("Failed to extract xpath " + xpath);
            else
                return null;
        }

        if (obj->type != XPath.ObjectType.STRING)
            throw new Boxes.Error.INVALID ("Failed to extract xpath " + xpath);

        return obj->stringval;
    }

    private void actor_add (Clutter.Actor actor, Clutter.Container container) {
        if (actor.get_parent () == (Clutter.Actor) container)
            return;

        actor_remove (actor);
        container.add (actor);
    }

    private void actor_remove (Clutter.Actor actor) {
        var container = actor.get_parent () as Clutter.Container;

        if (container == null)
            return;

        container.remove (actor);
    }

    private void actor_pin (Clutter.Actor actor) {
        actor.set_geometry (actor.get_geometry ());
    }

    private void actor_unpin (Clutter.Actor actor) {
        actor.set_size (-1, -1);
        actor.set_position (-1, -1);
    }
}
