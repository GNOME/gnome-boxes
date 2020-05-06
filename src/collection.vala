// This file is part of GNOME Boxes. License: LGPLv2+

private abstract class Boxes.CollectionItem: GLib.Object, Boxes.UI {
    public string name { set; get; }

    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    public virtual int compare (CollectionItem other) {
        // First machines before non-machines
        if (other is Machine)
            return 1;

        // Then non-machine
        // First by name
        if (is_set (name) && is_set (other.name))
            return name.collate (other.name);

        // Sort empty names last
        if (is_set (name))
            return -1;
        if (is_set (other.name))
            return 1;

        return 0;
    }
}

private class Boxes.Collection: GLib.Object {
    public signal void item_added (CollectionItem item);
    public signal void item_removed (CollectionItem item);

    public GLib.ListStore items;

    private GLib.List<CollectionItem> hidden_items;

    public uint length {
        get { return items.get_n_items (); }
    }

    public delegate void CollectionForeachFunc (CollectionItem item);

    construct {
        items = new GLib.ListStore (typeof (CollectionItem));
        hidden_items = new GLib.List<CollectionItem> ();
    }

    public Collection () {
    }

    public CollectionItem get_item (int position) {
        return items.get_item (position) as CollectionItem;
    }

    public void add_item (CollectionItem item) {
        var machine = item as Machine;

        if (machine == null) {
            warning ("Cannot add item %p".printf (&item));

            return;
        }

        var window = machine.window;
        if (window.ui_state == UIState.WIZARD) {
            // Don't show newly created items until user is out of wizard
            hidden_items.append (item);

            ulong ui_state_id = 0;
            ui_state_id = window.notify["ui-state"].connect (() => {
                if (window.ui_state == UIState.WIZARD)
                    return;

                if (hidden_items.find (item) != null) {
                    add_item (item);
                    hidden_items.remove (item);
                }
                window.disconnect (ui_state_id);
            });

            return;
        }

        item.set_state (window.ui_state);

        items.insert_sorted (item, (item1, item2) => {
            if (item1 == null || item2 == null)
                return 0;

            var collection_item1 = item1 as CollectionItem;
            var collection_item2 = item2 as CollectionItem;

            return collection_item1.compare (collection_item2);
        });

        item_added (item);
    }

    public void remove_item (CollectionItem item) {
        hidden_items.remove (item);
        for (int i = 0 ; i < length ; i++) {
           if (get_item (i) == item) {
                items.remove (i);
                item_removed (item);

                break;
            }
        }
    }

    public void foreach_item (CollectionForeachFunc foreach_func) {
        for (int i = 0 ; i < length ; i++)
            foreach_func (get_item (i));
    }
}

private class Boxes.CollectionFilter: GLib.Object {
    // Need a signal cause delegate properties aren't real properties and hence are not notified.
    public signal void filter_func_changed ();

    private string [] terms;

    private string _text;
    public string text {
        get { return _text; }
        set {
            _text = value;
            terms = value.split(" ");
            for (int i = 0; i < terms.length; i++)
                terms[i] = canonicalize_for_search (terms[i]);
        }
    }

    private unowned Boxes.CollectionFilterFunc _filter_func = null;
    public unowned Boxes.CollectionFilterFunc filter_func {
        get { return _filter_func; }
        set {
            _filter_func = value;
            filter_func_changed ();
        }
    }

    public bool filter (CollectionItem item) {
        var name = canonicalize_for_search (item.name);
        foreach (var term in terms) {
            if (! (term in name))
                return false;
        }

        if (filter_func != null)
            return filter_func (item);

        return true;
    }
}

private delegate bool Boxes.CollectionFilterFunc (Boxes.CollectionItem item);

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
