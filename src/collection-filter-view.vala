// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/collection-filter-view.ui")]
private class Boxes.CollectionFilterView: Gtk.Bin, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    [GtkChild]
    private Gtk.Stack stack;
    [GtkChild]
    private Boxes.IconView icon_view;
    [GtkChild]
    private Boxes.ListView list_view;

    public AppWindow.ViewType view_type { get; set; default = AppWindow.ViewType.ICON; }

    private unowned CollectionFilterFunc _filter_func = null;
    public unowned CollectionFilterFunc filter_func {
        get { return _filter_func; }
        set {
            _filter_func = value;
            icon_view.filter.filter_func = value;
            list_view.filter.filter_func = value;
        }
    }

    public ICollectionView view {
        get {
            switch (view_type) {
            default:
            case AppWindow.ViewType.ICON:
                return icon_view;
            case AppWindow.ViewType.LIST:
                return list_view;
            }
        }
    }

    construct {
        notify["view-type"].connect (ui_state_changed);
    }

    public void setup_ui (AppWindow window) {
        icon_view.setup_ui (window);
        list_view.setup_ui (window);
    }

    public void foreach_view (Func<ICollectionView> func) {
        func (icon_view);
        func (list_view);
    }

    private void ui_state_changed () {
        icon_view.set_state (ui_state);
        list_view.set_state (ui_state);

        if (ui_state == UIState.COLLECTION) {
            stack.visible_child = view;

            icon_view.show ();
            list_view.show ();
        }
    }
}
