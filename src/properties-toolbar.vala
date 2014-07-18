// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/properties-toolbar.ui")]
private class Boxes.PropertiesToolbar: HeaderBar {
    [GtkChild]
    private Image back_image;

    private AppWindow window;

    construct {
        back_image.icon_name = (get_direction () == TextDirection.RTL)? "go-previous-rtl-symbolic" :
                                                                        "go-previous-symbolic";
    }

    public void setup_ui (AppWindow window) {
        this.window = window;
    }

    [GtkCallback]
    private void on_back_clicked () {
        window.set_state (window.previous_ui_state);
    }
}
