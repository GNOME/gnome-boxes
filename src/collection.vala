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

    private GLib.ListStore items;
    public GLib.ListStore filtered_items;
    private CollectionFilter collection_filter = new CollectionFilter ();
    private CompareDataFunc<CollectionItem> sort_func = ((item1, item2) => {
        return item1.compare (item2);
    });

    private GLib.List<CollectionItem> hidden_items;

    public uint length {
        get { return items.get_n_items (); }
    }

    public delegate void CollectionForeachFunc (CollectionItem item);

    construct {
        items = new GLib.ListStore (typeof (CollectionItem));
        filtered_items = new GLib.ListStore (typeof (CollectionItem));
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
        items.insert_sorted (item, sort_func);
        filtered_items.insert_sorted (item, sort_func);

        item_added (item);
    }

    public void remove_item (CollectionItem item) {
        hidden_items.remove (item);
        for (int i = 0 ; i < length ; i++) {
           if (get_item (i) == item) {
                items.remove (i);
                filtered_items.remove (i);

                item_removed (item);

                break;
            }
        }
    }

    public void foreach_item (CollectionForeachFunc foreach_func) {
        for (int i = 0 ; i < length ; i++)
            foreach_func (get_item (i));
    }

    public void filter (string search_term) {
        filtered_items.remove_all ();

        collection_filter.text = search_term;
        foreach_item ((item) => {
            if (collection_filter.filter (item)) {
                filtered_items.insert_sorted (item, sort_func);
            }
        });
    }
}

private class Boxes.CollectionFilter: GLib.Object {
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

    public bool filter (CollectionItem item) {
        var name = canonicalize_for_search (item.name);
        foreach (var term in terms) {
            if (! (term in name))
                return false;
        }

        return true;
    }
}
