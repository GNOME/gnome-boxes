// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/selection-toolbar.ui")]
private class Boxes.SelectionToolbar: Hdy.HeaderBar {
    [GtkChild]
    private Button search_btn;
    [GtkChild]
    private MenuButton menu_button;
    [GtkChild]
    private Label menu_button_label;

    private AppWindow window;

    [GtkCallback]
    private void on_cancel_btn_clicked () {
        window.selection_mode = false;
    }

    construct {
        // Work around for https://bugzilla.gnome.org/show_bug.cgi?id=734676
        custom_title = menu_button;

        App.app.notify["selected-items"].connect (() => {
            update_selection_label ();
        });
    }

    public void setup_ui (AppWindow window) {
        this.window = window;

        update_selection_label ();

        update_search_btn ();
        App.app.collection.item_added.connect (update_search_btn);
        App.app.collection.item_removed.connect (update_search_btn);

        search_btn.bind_property ("active", window.searchbar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);
    }

    private void update_selection_label () {
        var items = App.app.selected_items.length ();
        if (items > 0) {
            // This goes with the "Click on items to select them" string and is about selection of items (boxes)
            // when the main collection view is in selection mode.
            menu_button_label.label = ngettext ("%u selected", "%u selected", items).printf (items);
        } else {
            menu_button_label.label = _("(Click on items to select them)");
        }
    }

    private void update_search_btn () {
        search_btn.sensitive = App.app.collection.length != 0;
    }
}
