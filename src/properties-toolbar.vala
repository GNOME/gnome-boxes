// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/properties-toolbar.ui")]
private class Boxes.PropertiesToolbar: HeaderBar {
    [GtkChild]
    private Image back_image;

    construct {
        back_image.icon_name = (get_direction () == TextDirection.RTL)? "go-previous-rtl-symbolic" :
                                                                        "go-previous-symbolic";
    }

    [GtkCallback]
    private void on_back_clicked () {
        App.app.set_state (App.app.previous_ui_state);
    }
}
