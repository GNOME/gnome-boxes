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

public class Boxes.CollectionItem: GLib.Object {
    public string name;
}

public class Boxes.Collection: GLib.Object {
    public signal void item_added (CollectionItem item);

    GenericArray<CollectionItem> items;

    public Collection () {
        this.items = new GenericArray<CollectionItem> ();
    }

    public void add_item (CollectionItem item) {
        this.items.add (item);
        this.item_added (item);
    }
}

public class Boxes.Category: GLib.Object {
    public string name;

    public Category (string name) {
        this.name = name;
    }
}
