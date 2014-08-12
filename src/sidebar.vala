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

    [GtkChild]
    public WizardSidebar wizard_sidebar;
    [GtkChild]
    public PropertiesSidebar props_sidebar;
    [GtkChild]
    private Gtk.Notebook notebook;

    private AppWindow window;

    construct {
        notify["ui-state"].connect (ui_state_changed);
    }

    public void setup_ui (AppWindow window) {
        this.window = window;
        props_sidebar.setup_ui (window);
    }

    private void ui_state_changed () {
        switch (ui_state) {
        case UIState.WIZARD:
        case UIState.PROPERTIES:
            reveal_child = true;
            notebook.page = ui_state == UIState.WIZARD ? SidebarPage.WIZARD : SidebarPage.PROPERTIES;
            break;

        default:
            reveal_child = false;
            break;
        }
    }
}
