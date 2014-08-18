// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private enum Boxes.PropertiesPage {
    LOGIN,
    SYSTEM,
    DISPLAY,
    DEVICES,

    LAST,
}

private class Boxes.Properties: Gtk.Stack, Boxes.UI {
    private const string[] page_names = { "login", "system", "display", "devices" };

    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private AppWindow window;

    private ulong stats_id;
    private bool restore_fullscreen;

    private PropertiesPage _page;
    public PropertiesPage page {
        get { return _page; }
        set {
            _page = value;

            visible_child_name = page_names[value];
        }
    }

    private class PageWidget: Gtk.Box {
        public bool empty;

        private Gtk.Grid grid;
        private List<Boxes.Property> properties;

        public signal void refresh_properties ();

        public PageWidget (PropertiesPage page, Machine machine) {
            switch (page) {
            case PropertiesPage.LOGIN:
                name = _("Login");
                break;

            case PropertiesPage.SYSTEM:
                name = _("System");
                break;

            case PropertiesPage.DISPLAY:
                name = _("Display");
                break;

            case PropertiesPage.DEVICES:
                name = _("Devices");
                break;
            }

            get_style_context ().add_class ("content-bg");
            get_style_context ().add_class ("transparent-bg");

            grid = new Gtk.Grid ();
            grid.margin = 20;
            grid.row_spacing = 10;
            grid.column_spacing = 20;
            grid.valign = Gtk.Align.START;
            pack_end (grid, true, true);

            PropertyCreationFlag flags = PropertyCreationFlag.NONE;
            properties = machine.get_properties (page, ref flags);
            empty = properties.length () == 0;
            if (!empty) {
                int current_row = 1;
                foreach (var property in properties) {
                    if (property.description != null) {
                        var label_name = new Gtk.Label (property.description);
                        label_name.get_style_context ().add_class ("boxes-property-name-label");
                        label_name.margin_left = 25;
                        label_name.halign = Gtk.Align.START;
                        label_name.hexpand = false;
                        grid.attach (label_name, 0, current_row, 1, 1);
                        var widget = property.widget;
                        widget.hexpand = true;
                        grid.attach (widget, 1, current_row, 1, 1);
                    } else {
                        var widget = property.widget;
                        widget.hexpand = true;
                        widget.margin_left = 25;
                        grid.attach (widget, 0, current_row, 2, 1);
                    }

                    var widget = property.extra_widget;
                    if (widget != null) {
                        current_row += 1;
                        widget.margin_left = 25;
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

    private void list_append (Gtk.ListStore listmodel, string label, bool visible) {
        Gtk.TreeIter iter;

        listmodel.append (out iter);
        listmodel.set (iter, 0, label);
        listmodel.set (iter, 1, visible);
    }

    private void populate () {
        window.sidebar.props_sidebar.listmodel.clear ();
        foreach (var page in get_children ())
            remove (page);

        var machine = window.current_item as Machine;
        var libvirt_machine = window.current_item as LibvirtMachine;

        window.sidebar.props_sidebar.shutdown_button.sensitive = libvirt_machine != null &&
                                                                 libvirt_machine.is_running ();

        if (machine == null)
            return;

        for (var i = 0; i < PropertiesPage.LAST; i++) {
            var page = new PageWidget (i, machine);
            add_named (page, page_names[i]);
            set_data<PageWidget> (@"boxes-property-$i", page);

            page.refresh_properties.connect (() => {
                var current_page = page;
                this.populate ();
                var path = new Gtk.TreePath.from_indices (current_page);
                window.sidebar.props_sidebar.selection.select_path (path);
                page = current_page;
            });

            list_append (window.sidebar.props_sidebar.listmodel, page.name, !page.empty);
        }

        PropertiesPage current_page;

        if (libvirt_machine != null)
            current_page = (previous_ui_state == UIState.WIZARD) ? PropertiesPage.SYSTEM : PropertiesPage.LOGIN;
        else
            current_page = PropertiesPage.LOGIN;

        var path = new Gtk.TreePath.from_indices (current_page);
        window.sidebar.props_sidebar.selection.select_path (path);
        visible_child_name = page_names[current_page];
    }

    public void setup_ui (AppWindow window) {
        this.window = window;

        transition_type = Gtk.StackTransitionType.SLIDE_UP_DOWN;
        transition_duration = 400;

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

            if (window.current_item is LibvirtMachine) {
                var libvirt_machine = window.current_item as LibvirtMachine;
                stats_id = libvirt_machine.stats_updated.connect (() => {
                    window.sidebar.props_sidebar.cpu_graph.points = libvirt_machine.cpu_stats;
                    window.sidebar.props_sidebar.net_graph.points = libvirt_machine.net_stats;
                    window.sidebar.props_sidebar.io_graph.points = libvirt_machine.io_stats;
                });
            }

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
