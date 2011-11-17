// This file is part of GNOME Boxes. License: LGPLv2+

private abstract class Boxes.CollectionItem: Boxes.UI {
    public string name { set; get; }
}

private class Boxes.Collection: GLib.Object {
    private Boxes.App app;
    public signal void item_added (CollectionItem item);

    public GenericArray<CollectionItem> items;

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
    public enum Kind {
        USER,
        NEW,
        FAVORITES,
        PRIVATE,
        SHARED
    }

    public string name;
    public Kind kind;

    public Category (string name, Kind kind = Kind.USER) {
        this.name = name;
        this.kind = kind;
    }
}
