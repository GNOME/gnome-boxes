// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/identify-os-page.ui")]
public class Boxes.IdentifyOsPage : Gtk.Box {
    private Boxes.IdentifyOsPopover os_popover;

    [GtkChild]
    private unowned Gtk.MenuButton menu_button;
    [GtkChild]
    private unowned Gtk.Label menu_button_label;

    private Osinfo.Os? selected_os = null;

    construct {
        os_popover = new Boxes.IdentifyOsPopover ();
        os_popover.os_selected.connect (on_os_selected);

        menu_button.popover = os_popover;
    }

    public Osinfo.Os? get_selected_os () {
        return selected_os;
    }

    private void on_os_selected (Osinfo.Os? os) {
        this.selected_os = os;

        if (selected_os != null)
            menu_button_label.set_label (os.get_name ().replace ("Unknown", ""));
        else
            menu_button_label.set_label (_("Unknown OS"));
    }
}
