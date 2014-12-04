// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/properties-toolbar.ui")]
private class Boxes.PropertiesToolbar: HeaderBar {
    [GtkChild]
    public Gtk.Button back_button;
    [GtkChild]
    private EditableEntry title_entry;

    private AppWindow window;
    private unowned PropertiesWindow props_window;

    private CollectionItem item;
    private ulong item_name_id;

    construct {
        // Work around for https://bugzilla.gnome.org/show_bug.cgi?id=734676
        set_custom_title (title_entry);
    }

    public void setup_ui (AppWindow window, PropertiesWindow props_window) {
        this.window = window;
        this.props_window = props_window;

        window.notify["ui-state"].connect (ui_state_changed);
    }

    [GtkCallback]
    private void on_back_clicked () {
        props_window.revert_state ();
    }

    [GtkCallback]
    private void on_title_entry_changed () {
        window.current_item.name = title_entry.text;
    }

    private void ui_state_changed () {
        back_button.visible = (window.previous_ui_state == UIState.WIZARD);
        show_close_button = (window.previous_ui_state != UIState.WIZARD);

        if (item_name_id != 0) {
            item.disconnect (item_name_id);
            item_name_id = 0;
        }

        if (window.ui_state == UIState.PROPERTIES) {
            item = window.current_item;

            item_name_id = item.notify["name"].connect (() => {
                title_entry.text = item.name;
            });
            title_entry.text = item.name;
        }
    }
}
