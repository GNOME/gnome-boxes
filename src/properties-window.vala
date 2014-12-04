// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private enum Boxes.PropsWindowPage {
    MAIN,
    TROUBLESHOOTING_LOG
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/properties-window.ui")]
private class Boxes.PropertiesWindow: Gtk.Window, Boxes.UI {
    public const string[] page_names = { "main", "troubleshooting_log" };

    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private PropsWindowPage _page;
    public PropsWindowPage page {
        get { return _page; }
        set {
            _page = value;

            view.visible_child_name = page_names[value];
        }
    }

    [GtkChild]
    public Gtk.Stack view;
    [GtkChild]
    public Properties properties;
    [GtkChild]
    public TroubleshootLog troubleshoot_log;
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

    public void show_troubleshoot_log (string log) {
        troubleshoot_log.view.buffer.text = log;
        page = PropsWindowPage.TROUBLESHOOTING_LOG;
    }

    public void copy_troubleshooting_log_to_clipboard () {
        var log = troubleshoot_log.view.buffer.text;
        var clipboard = Gtk.Clipboard.get_for_display (get_display (), Gdk.SELECTION_CLIPBOARD);

        clipboard.set_text (log, -1);
    }

    public void revert_state () {
        if ((app_window.current_item as Machine).state != Machine.MachineState.RUNNING &&
             app_window.previous_ui_state == UIState.DISPLAY)
            app_window.set_state (UIState.COLLECTION);
        else
            app_window.set_state (app_window.previous_ui_state);

        page = PropsWindowPage.MAIN;
    }

    private void ui_state_changed () {
        properties.set_state (ui_state);

        visible = (ui_state == UIState.PROPERTIES);
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
