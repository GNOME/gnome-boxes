// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/properties-page-widget.ui")]
private class Boxes.PropertiesPageWidget: Gtk.Box {
    public bool empty;

    [GtkChild]
    private unowned Gtk.Grid grid;
    private List<Boxes.Property> properties;

    public signal void refresh_properties ();

    public PropertiesPageWidget (PropertiesPage page, Machine machine) {
        switch (page) {
        case PropertiesPage.GENERAL:
            name = _("General");
            break;

        case PropertiesPage.SYSTEM:
            name = _("System");
            break;

        case PropertiesPage.DEVICES:
            name = _("Devices & Shares");
            break;

        case PropertiesPage.SNAPSHOTS:
            name = _("Snapshots");
            break;
        }

        properties = machine.get_properties (page);
        empty = properties.length () == 0;
        if (!empty) {
            int current_row = 1;
            foreach (var property in properties) {
                if (property.description != null) {
                    grid.attach (property.label, 0, current_row, 1, 1);
                    grid.attach (property.widget, 1, current_row, 1, 1);
                } else {
                    grid.attach (property.widget, 0, current_row, 2, 1);
                }

                var widget = property.extra_widget;
                if (widget != null) {
                    current_row += 1;
                    grid.attach (widget, 0, current_row, 2, 1);
                }

                property.refresh_properties.connect (() => {
                    this.refresh_properties ();
                });
                current_row += 1;
            }
        }

        show_all ();
    }

    public bool flush_changes () {
        var reboot_required = false;

        foreach (var property in properties) {
            property.flush ();
            reboot_required |= property.reboot_required;
        }

        return reboot_required;
    }
}
