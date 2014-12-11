// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.PropertiesPageWidget: Gtk.Box {
    public bool empty;

    private Gtk.Grid grid;
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
            name = _("Devices");
            break;

        case PropertiesPage.SNAPSHOTS:
            name = _("Snapshots");
            break;
        }

        get_style_context ().add_class ("content-bg");
        get_style_context ().add_class ("transparent-bg");

        grid = new Gtk.Grid ();
        grid.margin = 20;
        grid.row_spacing = 10;
        grid.column_spacing = 20;
        grid.valign = Gtk.Align.START;
        var scrolled_win = new Gtk.ScrolledWindow (null, null);
        scrolled_win.margin_start = 20;
        scrolled_win.margin_end = 20;
        scrolled_win.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scrolled_win.add (grid);
        pack_end (scrolled_win, true, true);

        PropertyCreationFlag flags = PropertyCreationFlag.NONE;
        properties = machine.get_properties (page, ref flags);
        empty = properties.length () == 0;
        if (!empty) {
            int current_row = 1;
            foreach (var property in properties) {
                if (property.description != null) {
                    var label_name = new Gtk.Label (property.description);
                    label_name.get_style_context ().add_class ("boxes-property-name-label");
                    label_name.halign = Gtk.Align.START;
                    label_name.hexpand = false;
                    grid.attach (label_name, 0, current_row, 1, 1);
                    var widget = property.widget;
                    widget.hexpand = true;
                    grid.attach (widget, 1, current_row, 1, 1);
                } else {
                    var widget = property.widget;
                    widget.hexpand = true;
                    grid.attach (widget, 0, current_row, 2, 1);
                }

                var widget = property.extra_widget;
                if (widget != null) {
                    current_row += 1;
                    widget.hexpand = true;
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
