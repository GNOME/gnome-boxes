// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private enum Boxes.PropertiesPage {
    GENERAL,
    SYSTEM,
    DEVICES,
    SNAPSHOTS,

    LAST,
}

private class Boxes.Properties: Gtk.Notebook, Boxes.UI {
    private const string[] page_titles = { N_("General"), N_("System"), N_("Devices"), N_("Snapshots") };

    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private AppWindow window;

    private ulong stats_id;
    private bool restore_fullscreen;

    private class PageWidget: Gtk.Box {
        public bool empty;

        private Gtk.Grid grid;
        private List<Boxes.Property> properties;

        public signal void refresh_properties ();

        public PageWidget (PropertiesPage page, Machine machine) {
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
            scrolled_win.min_content_width = 640;
            scrolled_win.min_content_height = 480;
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

    construct {
        notify["ui-state"].connect (ui_state_changed);
    }

    private void populate () {
        foreach (var page in get_children ())
            remove (page);

        var machine = window.current_item as Machine;
        var libvirt_machine = window.current_item as LibvirtMachine;

        if (machine == null)
            return;

        for (var i = 0; i < PropertiesPage.LAST; i++) {
            var page = new PageWidget (i, machine);
            var label = new Gtk.Label (page_titles[i]);
            insert_page (page, label, i);
            set_data<PageWidget> (@"boxes-property-$i", page);

            page.refresh_properties.connect (() => {
                var current_page = page;
                this.populate ();
                page = current_page;
            });
        }

        if (libvirt_machine != null)
            page = (previous_ui_state == UIState.WIZARD) ? PropertiesPage.SYSTEM : PropertiesPage.GENERAL;
        else
            page = PropertiesPage.GENERAL;
    }

    public void setup_ui (AppWindow window, PropertiesWindow dialog) {
        this.window = window;

        show_all ();
    }

    private void ui_state_changed () {
        if (stats_id != 0) {
            window.current_item.disconnect (stats_id);
            stats_id = 0;
        }

        if (ui_state == UIState.PROPERTIES) {
            restore_fullscreen = (previous_ui_state == UIState.DISPLAY && window.fullscreened);
            window.fullscreened = false;

            populate ();
        } else if (previous_ui_state == UIState.PROPERTIES) {
            var reboot_required = false;

            for (var i = 0; i < PropertiesPage.LAST; i++) {
                var page = get_data<PageWidget> (@"boxes-property-$i");
                reboot_required |= page.flush_changes ();
            }

            var machine = window.current_item as Machine;
            if (reboot_required && (machine.is_on () || machine.state == Machine.MachineState.SAVED)) {
                var message = _("Changes require restart of '%s'.").printf (machine.name);
                window.notificationbar.display_for_action (message, _("_Restart"), () => {
                    machine.restart ();
                });
            }

            if (restore_fullscreen) {
                window.fullscreened = true;
                restore_fullscreen = false;
            }
        }
    }
}
