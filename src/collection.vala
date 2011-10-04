// This file is part of GNOME Boxes. License: LGPL2
using GLib;

private class Boxes.CollectionItem: GLib.Object {
    public string name;
}

private class Boxes.Collection: GLib.Object {
    public signal void item_added (CollectionItem item);

    GenericArray<CollectionItem> items;

    public Collection () {
        items = new GenericArray<CollectionItem> ();
    }

    public void add_item (CollectionItem item) {
        items.add (item);
        item_added (item);
    }
}

private class Boxes.Category: GLib.Object {
    public string name;

    public Category (string name) {
        this.name = name;
    }
}
