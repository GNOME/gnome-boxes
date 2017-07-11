// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/troubleshoot-view.ui")]
private class Boxes.TroubleshootView : Gtk.Stack, Boxes.UI {
    public UIState previous_ui_state { get; protected set; } 
    public UIState ui_state { get; protected set; }

    private AppWindow window;

    public void setup_ui (AppWindow window) {
        this.window = window;
    }
}
