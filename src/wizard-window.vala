// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private enum Boxes.WizardWindowPage {
    MAIN,
    CUSTOMIZATION,
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-window.ui")]
private class Boxes.WizardWindow : Gtk.Window, Boxes.UI {
    public const string[] page_names = { "main", "customization" };

    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private WizardWindowPage _page;
    public WizardWindowPage page {
        get { return _page; }
        set {
            if (_page == WizardWindowPage.CUSTOMIZATION && value != WizardWindowPage.CUSTOMIZATION &&
                resource_properties != null && resource_properties.length () > 0) {
                foreach (var property in resource_properties)
                    property.flush ();
                resource_properties = null;

                wizard.review.begin ();
            }

            _page = value;

            view.visible_child_name = page_names[value];
        }
    }

    [GtkChild]
    public Gtk.Stack view;
    [GtkChild]
    public Wizard wizard;
    [GtkChild]
    public Gtk.Grid customization_grid;
    [GtkChild]
    public WizardToolbar topbar;
    [GtkChild]
    public Notificationbar notificationbar;

    private GLib.List<Boxes.Property> resource_properties;

    public WizardWindow (AppWindow app_window) {
        wizard.setup_ui (app_window, this);
        topbar.setup_ui (this);

        set_transient_for (app_window);

        notify["ui-state"].connect (ui_state_changed);
    }

    public void show_customization_page (LibvirtMachine machine) {
        resource_properties = new GLib.List<Boxes.Property> ();
        machine.properties.get_resources_properties (ref resource_properties);

        return_if_fail (resource_properties.length () > 0);

        foreach (var child in customization_grid.get_children ())
            customization_grid.remove (child);

        var current_row = 0;
        foreach (var property in resource_properties) {
            if (property.widget == null || property.extra_widget == null || property.description == null) {
                warn_if_reached ();

                continue;
            }

            var label_name = new Gtk.Label (property.description);
            label_name.get_style_context ().add_class ("boxes-property-name-label");
            label_name.halign = Gtk.Align.START;
            label_name.hexpand = false;
            customization_grid.attach (label_name, 0, current_row, 1, 1);

            property.widget.hexpand = true;
            customization_grid.attach (property.widget, 1, current_row, 1, 1);

            property.extra_widget.hexpand = true;
            customization_grid.attach (property.extra_widget, 0, current_row + 1, 2, 1);

            current_row += 2;
        }
        customization_grid.show_all ();

        page = WizardWindowPage.CUSTOMIZATION;
    }

    private void ui_state_changed () {
        wizard.set_state (ui_state);

        this.visible = (ui_state == UIState.WIZARD);
    }

    [GtkCallback]
    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        var default_modifiers = Gtk.accelerator_get_default_mod_mask ();

        if (event.keyval == Gdk.Key.Left && // ALT + Left -> back
                   (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            topbar.click_back_button ();
            return true;
        } else if (event.keyval == Gdk.Key.Right && // ALT + Right -> forward
                   (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            topbar.click_forward_button ();
            return true;
        } else if (event.keyval == Gdk.Key.Escape) { // ESC -> cancel
            topbar.cancel_btn.clicked ();
        }

        return false;
    }

    [GtkCallback]
    private bool on_delete_event () {
        wizard.cancel ();

        return true;
    }
}
