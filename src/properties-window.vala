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
    [GtkChild]
    public Notificationbar notificationbar;

    private unowned AppWindow app_window;

    public PropertiesWindow (AppWindow app_window) {
        this.app_window = app_window;

        properties.setup_ui (app_window, this);
        topbar.setup_ui (app_window, this);

        set_transient_for (app_window);

        notify["ui-state"].connect (ui_state_changed);
    }

    public void revert_state () {
        if ((app_window.current_item as Machine).state != Machine.MachineState.RUNNING &&
             app_window.previous_ui_state == UIState.DISPLAY)
            app_window.set_state (UIState.COLLECTION);
        else
            app_window.set_state (app_window.previous_ui_state);
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
            revert_state ();

        return false;
    }

    [GtkCallback]
    private bool on_delete_event () {
        revert_state ();

        return true;
    }
}
