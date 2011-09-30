using GLib;

class CollectionItem: GLib.Object {
    public CollectionItem? parent = null;
    public string name;
}

class Collection: GLib.Object {
	public signal void item_added (CollectionItem item);

	GenericArray<CollectionItem> array = new GenericArray<CollectionItem> ();

	public void add_item (CollectionItem item) {
		array.add (item);
		item_added (item);
	}
}
