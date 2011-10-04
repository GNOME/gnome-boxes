using GLib;

class Boxes.CollectionItem: GLib.Object {
    public string name;
}

class Boxes.Collection: GLib.Object {
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

class Boxes.Category: GLib.Object {
    public string name;

    public Category (string name) {
        this.name = name;
    }
}
