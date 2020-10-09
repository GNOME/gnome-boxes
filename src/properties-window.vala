// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private enum Boxes.PropsWindowPage {
    MAIN,
    TROUBLESHOOTING_LOG,
    FILE_CHOOSER,
    TEXT_EDITOR,
}

public delegate void Boxes.FileChosenFunc (string path);

[GtkTemplate (ui = "/org/gnome/Boxes/ui/properties-window.ui")]
private class Boxes.PropertiesWindow: Gtk.Window, Boxes.UI {
    public const string[] page_names = { "main", "troubleshoot_log", "file_chooser", "config_editor" };

    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private PropsWindowPage _page;
    public PropsWindowPage page {
        get { return _page; }
        set {
            _page = value;

            view.visible_child_name = page_names[value];
            topbar.page = value;
        }
    }

    [GtkChild]
    public Gtk.Stack view;
    [GtkChild]
    public Properties properties;
    [GtkChild]
    public TroubleshootLog troubleshoot_log;
    [GtkChild]
    public MachineConfigEditor config_editor;

    public Gtk.FileChooserNative file_chooser;
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

        file_chooser = new Gtk.FileChooserNative (_("Select a device or ISO file"),
                                                  app_window,
                                                  Gtk.FileChooserAction.OPEN,
                                                  _("Open"), _("Cancel"));
        file_chooser.bind_property ("visible", this, "visible", BindingFlags.INVERT_BOOLEAN);

    }

    public void show_troubleshoot_log (string log) {
        troubleshoot_log.view.buffer.text = log;
        page = PropsWindowPage.TROUBLESHOOTING_LOG;
    }

    public void show_editor_view (LibvirtMachine machine) {
        page = PropsWindowPage.TEXT_EDITOR;
        config_editor.setup (machine);

        topbar.config_editor.set_title (machine.name);
    }

    public void show_file_chooser (owned FileChosenFunc file_chosen_func) {
        page = PropsWindowPage.FILE_CHOOSER;
        var res = file_chooser.run ();
        if (res == Gtk.ResponseType.ACCEPT) {
            file_chosen_func (file_chooser.get_filename ());
        }

        page = PropsWindowPage.MAIN;
    }

    public void copy_troubleshoot_log_to_clipboard () {
        var log = troubleshoot_log.view.buffer.text;
        var clipboard = Gtk.Clipboard.get_for_display (get_display (), Gdk.SELECTION_CLIPBOARD);

        clipboard.set_text (log, -1);
    }

    public void revert_state () {
        var current_machine = app_window.current_item as Machine;
        if (current_machine.state != Machine.MachineState.RUNNING &&
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
        var default_modifiers = Gtk.accelerator_get_default_mod_mask ();
        var direction = get_direction ();

        if (((direction == Gtk.TextDirection.LTR && // LTR
              event.keyval == Gdk.Key.Left) ||      // ALT + Left -> back
             (direction == Gtk.TextDirection.RTL && // RTL
              event.keyval == Gdk.Key.Right)) &&    // ALT + Right -> back
            (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            topbar.click_back_button ();

            return true;
        } else if (event.keyval == Gdk.Key.Escape) { // ESC -> back
            revert_state ();

            return true;
        }

        return false;
    }

    [GtkCallback]
    private bool on_delete_event () {
        notificationbar.dismiss_all ();
        revert_state ();

        return true;
    }
}
