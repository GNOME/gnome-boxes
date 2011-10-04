/*
 * Copyright (C) 2011 Red Hat, Inc.
 *
 * Authors: Marc-André Lureau <marcandre.lureau@gmail.com>
 *          Zeeshan Ali (Khattak) <zeeshanak@gnome.org>
 *
 * This file is part of GNOME Boxes.
 *
 * GNOME Boxes is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * GNOME Boxes is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

using GLib;
using Gtk;
using Config;
using Xml;

public string get_pkgdata (string? file_name = null) {
    return Path.build_filename (DATADIR, Config.PACKAGE_TARNAME, file_name);
}

public string get_style (string? file_name = null) {
    return Path.build_filename (get_pkgdata (), "style", file_name);
}

public string get_pkgcache (string? file_name = null) {
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

public void tree_view_activate_on_single_click (Gtk.TreeView tree_view, bool should_activate) {
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
                    tree_view.get_path_at_pos ((int)event.x, (int)event.y, out path, out column, out x, out y);
                    if (path != null)
                        tree_view.row_activated (path, column);
            }

            return false;
        });
        tree_view.set_data<ulong> ("boxes-tree-view-activate", id);
    }
}

public async void output_stream_write (OutputStream stream, uint8[] buffer) throws GLib.IOError {
    var length = buffer.length;
    ssize_t i = 0;

    while (i < length)
        i += yield stream.write_async (buffer[i:length]);
}

public string? extract_xpath (string xmldoc, string xpath, bool required = false) throws Boxes.Error {
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

public void actor_add (Clutter.Actor actor, Clutter.Container container) {
    if (actor.get_parent () == (Clutter.Actor) container)
        return;

    actor_remove (actor);
    container.add (actor);
}

public void actor_remove (Clutter.Actor actor) {
    var container = actor.get_parent () as Clutter.Container;

    if (container == null)
        return;

    container.remove (actor);
}
