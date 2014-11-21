// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/properties-window.ui")]
private class Boxes.PropertiesWindow: Gtk.Window, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    [GtkChild]
    public Properties properties;
    [GtkChild]
    public PropertiesToolbar topbar;

    private unowned AppWindow app_window;

    public PropertiesWindow (AppWindow app_window) {
        this.app_window = app_window;

        properties.setup_ui (app_window, this);
        topbar.setup_ui (app_window);

        set_transient_for (app_window);

        notify["ui-state"].connect (ui_state_changed);
    }

    private void ui_state_changed () {
        properties.set_state (ui_state);

        visible = (ui_state == UIState.PROPERTIES);
        topbar.back_button.visible = (previous_ui_state == UIState.WIZARD);
        topbar.show_close_button = (previous_ui_state != UIState.WIZARD);
    }

    [GtkCallback]
    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        if (event.keyval == Gdk.Key.Escape) // ESC -> back
            topbar.back_button.clicked ();

        return false;
    }

    [GtkCallback]
    private bool on_delete_event () {
        topbar.back_button.clicked ();

        return true;
    }
}
