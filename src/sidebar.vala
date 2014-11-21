// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

private enum Boxes.SidebarPage {
    WIZARD,
    PROPERTIES,
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/sidebar.ui")]
private class Boxes.Sidebar: Gtk.Revealer, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private AppWindow window;

    construct {
        notify["ui-state"].connect (ui_state_changed);
    }

    public void setup_ui (AppWindow window) {
        this.window = window;
    }

    private void ui_state_changed () {
        switch (ui_state) {
        case UIState.PROPERTIES:
            reveal_child = true;
            break;

        default:
            reveal_child = false;
            break;
        }
    }
}
