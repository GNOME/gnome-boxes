// This file is part of GNOME Boxes. License: LGPLv2+

private abstract class Boxes.CollectionItem: Boxes.UI {
    public string name { set; get; }
}

private class Boxes.Collection: GLib.Object {
    public signal void item_added (CollectionItem item);
    public signal void item_removed (CollectionItem item);

    public GenericArray<CollectionItem> items;

    construct {
        items = new GenericArray<CollectionItem> ();
    }

    public Collection () {
    }

    public void add_item (CollectionItem item) {
        items.add (item);
        item_added (item);
    }

    public void remove_item (CollectionItem item) {
        items.remove (item);
        item_removed (item);
    }
}

private class Boxes.CollectionFilter: GLib.Object {
    private string [] terms;

    public string text {
        set {
            terms = value.split(" ");
            for (int i = 0; i < terms.length; i++)
                terms[i] = canonicalize_for_search (terms[i]);
        }
    }

    public bool filter (CollectionItem item) {
        var name = canonicalize_for_search (item.name);
        foreach (var term in terms) {
            if (! (term in name))
                return false;
        }
        return true;
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
