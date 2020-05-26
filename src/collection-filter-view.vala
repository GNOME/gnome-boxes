// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/collection-filter-view.ui")]
private class Boxes.CollectionFilterView: Gtk.Bin, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    public enum FilterType {
        ALL,
        FAVORITES,
    }

    [GtkChild]
    private Gtk.Stack stack;
    [GtkChild]
    private Boxes.IconView icon_view;
    [GtkChild]
    private Boxes.ListView list_view;

    public AppWindow.ViewType view_type { get; set; default = AppWindow.ViewType.ICON; }

    private FilterType _filter_type = FilterType.ALL;
    public FilterType filter_type {
        get { return _filter_type; }
        set {
            _filter_type = value;

            CollectionFilterFunc? filter_func = null;
            switch (filter_type) {
            default:
            case FilterType.ALL:
                filter_func = null;
                break;
            case FilterType.FAVORITES:
                filter_func = favorites_filter_func;
                break;
            }

            icon_view.filter.filter_func = filter_func;
            list_view.filter.filter_func = filter_func;
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
        notify["view-type"].connect (ui_state_changed);    }

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

    private bool favorites_filter_func (Boxes.CollectionItem item) {
        assert (item != null && item is Machine);
        var machine = item as Machine;

        return "favorite" in machine.config.categories;
    }
}
