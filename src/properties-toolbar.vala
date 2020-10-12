// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/properties-toolbar.ui")]
private class Boxes.PropertiesToolbar: Gtk.Stack {
    private PropsWindowPage _page;
    public PropsWindowPage page {
        get { return _page; }
        set {
            _page = value;

            visible_child_name = PropertiesWindow.page_names[value];
        }
    }

    [GtkChild]
    public Gtk.HeaderBar main;

    [GtkChild]
    public Gtk.HeaderBar config_editor;
    [GtkChild]
    public Gtk.Button apply_config_button;

    [GtkChild]
    public Gtk.Button troubleshooting_back_button;

    [GtkChild]
    private EditableEntry title_entry;

    private AppWindow window;
    private unowned PropertiesWindow props_window;

    private CollectionItem item;
    private ulong item_name_id;

    construct {
        // Work around for https://bugzilla.gnome.org/show_bug.cgi?id=734676
        main.set_custom_title (title_entry);
    }

    public void setup_ui (AppWindow window, PropertiesWindow props_window) {
        this.window = window;
        this.props_window = props_window;

        window.notify["ui-state"].connect (ui_state_changed);
        apply_config_button.notify["sensitive"].connect (on_apply_config_editor_sensitivity_changed);
    }

    public void click_back_button () {
        if (page != PropsWindowPage.TROUBLESHOOTING_LOG)
            return;

        troubleshooting_back_button.clicked ();
    }

    [GtkCallback]
    private void on_troubleshooting_back_clicked () requires (page == PropsWindowPage.TROUBLESHOOTING_LOG || page == PropsWindowPage.TEXT_EDITOR) {
        props_window.page = PropsWindowPage.MAIN;
    }

    [GtkCallback]
    private void on_copy_clipboard_clicked () requires (page == PropsWindowPage.TROUBLESHOOTING_LOG) {
        props_window.copy_troubleshoot_log_to_clipboard ();
    }

    [GtkCallback]
    private void on_config_editor_apply_config_clicked () {
        props_window.config_editor.apply ();
        apply_config_button.sensitive = false;
    }

    private void on_apply_config_editor_sensitivity_changed () {
        if (apply_config_button.sensitive) {
            config_editor.set_title ("*" + config_editor.get_title ());
        } else {
            config_editor.set_title (config_editor.get_title ().substring (1));
        }
    }

    [GtkCallback]
    private void on_title_entry_changed () {
        window.current_item.name = title_entry.text;
    }

    private void ui_state_changed () {
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
