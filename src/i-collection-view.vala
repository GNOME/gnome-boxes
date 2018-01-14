// This file is part of GNOME Boxes. License: LGPLv2+

private interface Boxes.ICollectionView: Gtk.Widget {
    public abstract CollectionFilter filter { get; protected set; }

    public abstract List<CollectionItem> get_selected_items ();
    public abstract void activate_first_item ();
    public abstract void select_by_criteria (SelectionCriteria criteria);
    public abstract void select_all ();
}
