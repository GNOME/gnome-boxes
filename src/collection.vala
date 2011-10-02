using GLib;

class Boxes.CollectionItem: GLib.Object {
    GenericArray<Category> categories = new GenericArray<Category> ();

    public string name;
}

class Boxes.Collection: GLib.Object {
    public signal void item_added (CollectionItem item);

    GenericArray<CollectionItem> array = new GenericArray<CollectionItem> ();

    public void add_item (CollectionItem item) {
        array.add (item);
        item_added (item);
    }
}

class Boxes.Category: GLib.Object {
    public string name;

    public Category (string name) {
        this.name = name;
    }

    // public bool item_filter (CollectionItem item) {
    //     return true;
    // }
}
