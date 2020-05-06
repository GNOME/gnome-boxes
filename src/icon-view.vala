// This file is part of GNOME Boxes. License: LGPLv2+

public enum Boxes.SelectionCriteria {
    ALL,
    NONE,
    RUNNING
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/icon-view.ui")]
private class Boxes.IconView: Gtk.ScrolledWindow, Boxes.ICollectionView, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    public CollectionFilter filter { get; protected set; }

    [GtkChild]
    private Gtk.FlowBox flowbox;

    private AppWindow window;
    private Boxes.ActionsPopover context_popover;

    private Category _category;
    public Category category {
        get { return _category; }
        set {
            _category = value;
            // FIXME: update view
        }
    }

    construct {
        category = new Category (_("New and Recent"), Category.Kind.NEW);

        filter = new CollectionFilter ();
        filter.notify["text"].connect (() => {
            flowbox.invalidate_filter ();
        });
        filter.filter_func_changed.connect (() => {
            flowbox.invalidate_filter ();
        });

        setup_flowbox ();

        notify["ui-state"].connect (ui_state_changed);
    }

    public void setup_ui (AppWindow window) {
        this.window = window;

        window.notify["selection-mode"].connect (() => {
            flowbox.selection_mode = window.selection_mode ? Gtk.SelectionMode.MULTIPLE :
                                                             Gtk.SelectionMode.NONE;
            update_selection_mode ();
        });

        context_popover = new Boxes.ActionsPopover (window);
    }

    public void select_by_criteria (SelectionCriteria criteria) {
        window.selection_mode = true;

        switch (criteria) {
        default:
        case SelectionCriteria.ALL:
            foreach_child ((box_child) => { select_child (box_child); });

            break;
        case SelectionCriteria.NONE:
            foreach_child ((box_child) => { unselect_child (box_child); });

            break;
        case SelectionCriteria.RUNNING:
            foreach_child ((box_child) => {
                var item = get_item_for_child (box_child);
                if (item != null && item is Machine) {
                    var machine = item as Machine;
                    if (machine.is_running)
                        select_child (box_child);
                } else
                    unselect_child (box_child);
            });

            break;
        }

        App.app.notify_property ("selected-items");
    }

    public List<CollectionItem> get_selected_items () {
        var selected = new List<CollectionItem> ();

        foreach (var box_child in flowbox.get_selected_children ()) {
            var item = get_item_for_child (box_child);
            selected.append (item);
        }

        return (owned) selected;
    }

    public void activate_first_item () {
        Gtk.FlowBoxChild first_child = null;
        foreach_child ((box_child) => {
            if (first_child == null)
                first_child = box_child;
        });

        if (first_child == null)
            flowbox.child_activated (first_child);
    }

    private void setup_flowbox () {
        flowbox.bind_model (App.app.collection.items, (item) => {
            var child = new Gtk.FlowBoxChild ();
            child.halign = Gtk.Align.START;
            var box = new IconViewChild (item as CollectionItem);
            child.add (box);

            box.notify["selected"].connect (() => {
                propagate_view_child_selection (child);
            });

            box.visible = true;
            child.visible = true;

            return child;
        });

        flowbox.set_filter_func (model_filter);
    }

    private CollectionItem? get_item_for_child (Gtk.FlowBoxChild child) {
        var view = child.get_child () as IconViewChild;
        if (view == null)
            return null;

        return view.item;
    }

    private void foreach_child (Func<Gtk.FlowBoxChild> func) {
        flowbox.forall ((child) => {
            var view_child = child as Gtk.FlowBoxChild;
            if (view_child == null)
                return;

            func (view_child);
        });
    }

    private bool model_filter (Gtk.FlowBoxChild child) {
        if (child  == null)
            return false;

        var item = get_item_for_child (child);
        if (item  == null)
            return false;

        return filter.filter (item as CollectionItem);
    }

    private void ui_state_changed () {
        if (ui_state == UIState.COLLECTION)
            flowbox.unselect_all ();
    }

    [GtkCallback]
    private void on_child_activated (Gtk.FlowBoxChild child) {
        if (window.selection_mode) {
            var view_child = child.get_child () as IconViewChild;
            if (view_child.selected)
                unselect_child (child);
            else
                select_child (child);

            return;
        }

        var item = get_item_for_child (child);
        if (item is LibvirtMachine) {
            var machine = item as LibvirtMachine;
            if (machine.importing)
                return;
        }

        window.select_item (item);

        update_selection_mode ();
    }

    [GtkCallback]
    private bool on_button_press_event (Gdk.EventButton event) {
        if (event.type != Gdk.EventType.BUTTON_RELEASE || event.button != 3)
            return false;

        var child = flowbox.get_child_at_pos ((int) event.x, (int) event.y);

        return launch_context_popover_for_child (child);
    }

    [GtkCallback]
    private bool on_key_press_event (Gdk.EventKey event) {
        if (event.keyval != Gdk.Key.Menu)
            return false;

        var child = flowbox.get_selected_children ().nth_data (0);
        if (child == null)
            return false;

        return launch_context_popover_for_child (child);
    }

    private bool launch_context_popover_for_child (Gtk.FlowBoxChild child) {
        var item = get_item_for_child (child);
        if (item == null)
            return false;

        var icon_view_child = child.get_child () as IconViewChild;
        var thumbnail = icon_view_child.thumbnail;

        context_popover.update_for_item (item);
        context_popover.set_relative_to (thumbnail);
        context_popover.show ();

        return true;
    }

    private void update_selection_mode () {
        foreach_child ((child) => {
            var view_child = child.get_child () as Boxes.IconViewChild;

            if (view_child.selection_mode != window.selection_mode)
                view_child.selection_mode = window.selection_mode;

            unselect_child (child);
        });
    }

    private void propagate_view_child_selection (Gtk.FlowBoxChild child) {
        var view_child = child.get_child () as IconViewChild;

        if (view_child.selected)
            select_child (child);
        else
            unselect_child (child);
    }

    private void select_child (Gtk.FlowBoxChild child) {
        var view_child = child.get_child () as IconViewChild;

        flowbox.select_child (child);
        if (!view_child.selected)
            view_child.selected = true;

        App.app.notify_property ("selected-items");
    }

    private void unselect_child (Gtk.FlowBoxChild child) {
        var view_child = child.get_child () as IconViewChild;

        flowbox.unselect_child (child);
        if (view_child.selected)
            view_child.selected = false;

        App.app.notify_property ("selected-items");
    }

    public void unselect_all () {
        flowbox.unselect_all ();

        foreach_child (unselect_child);

        App.app.notify_property ("selected-items");
    }

    public void select_all () {
        flowbox.select_all ();

        foreach_child (select_child);

        App.app.notify_property ("selected-items");
    }
}
