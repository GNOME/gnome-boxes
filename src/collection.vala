// This file is part of GNOME Boxes. License: LGPLv2

private abstract class Boxes.CollectionItem: Boxes.UI {
    public string name;
}

private class Boxes.Collection: GLib.Object {
    private Boxes.App app;
    public signal void item_added (CollectionItem item);

    GenericArray<CollectionItem> items;

    construct {
        items = new GenericArray<CollectionItem> ();
    }

    public Collection (Boxes.App app) {
        this.app = app;
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
