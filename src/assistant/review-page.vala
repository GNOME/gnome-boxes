using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/review-page.ui")]
private class Boxes.AssistantReviewPage : AssistantPage {
    [GtkChild]
    private WizardSummary summary;
    [GtkChild]
    private InfoBar nokvm_infobar;
    [GtkChild]
    private Grid customization_grid;
    [GtkChild]
    private ToggleButton customize_button;
    [GtkChild]
    private Stack customization_stack;
    private GLib.List<Boxes.Property> resource_properties;

    private Cancellable cancellable = new GLib.Cancellable ();

    [GtkCallback]
    private void on_customize_button_toggled () {
        customization_stack.set_visible_child (customize_button.active ?
                                               customization_grid : summary);
    }

    public async void setup (VMCreator vm_creator) {
        resource_properties = new GLib.List<Boxes.Property> ();

        try {
            artifact = yield vm_creator.create_vm (cancellable);
        } catch (IOError.CANCELLED cancel_error) { // We did this, so ignore!
        } catch (GLib.Error error) {
            warning ("Box setup failed: %s", error.message);
        }

        yield populate (artifact as LibvirtMachine);
    }

    public async void populate (LibvirtMachine machine) {
        var vm_creator = machine.vm_creator;
        foreach (var property in vm_creator.install_media.get_vm_properties ())
            summary.add_property (property.first, property.second);

        try {
            var config = null as GVirConfig.Domain;
            yield App.app.async_launcher.launch (() => {
                config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            });

            var memory = format_size (config.memory * Osinfo.KIBIBYTES, FormatSizeFlags.IEC_UNITS);
            summary.add_property (_("Memory"), memory);
        } catch (GLib.Error error) {
            warning ("Failed to get configuration for machine '%s': %s", machine.name, error.message);
        }

        if (!machine.importing && machine.storage_volume != null) {
            try {
                var volume_info = machine.storage_volume.get_info ();
                var capacity = format_size (volume_info.capacity);
                summary.add_property (_("Disk"),
                                      // Translators: This is disk size. E.g "1 GB maximum".
                                      _("%s maximum").printf (capacity));
            } catch (GLib.Error error) {
                warning ("Failed to get information on volume '%s': %s",
                         machine.storage_volume.get_name (),
                         error.message);
            }

        }

        nokvm_infobar.visible = (machine.domain_config.get_virt_type () != GVirConfig.DomainVirtType.KVM);

        populate_customization_grid (machine);
    }

    private void populate_customization_grid (LibvirtMachine machine) {
        machine.properties.get_resources_properties (ref resource_properties);

        return_if_fail (resource_properties.length () > 0);

        var current_row = 0;
        foreach (var property in resource_properties) {
            if (property.widget == null || property.extra_widget == null) {
                continue;
            }

            property.widget.hexpand = true;
            customization_grid.attach (property.widget, 0, current_row, 1, 1);

            property.extra_widget.hexpand = true;
            customization_grid.attach (property.extra_widget, 0, current_row + 1, 1, 1);

            current_row += 2;
        }
        customization_grid.show_all ();
    }

    public override void cleanup () {
        cancellable.cancel ();

        summary.clear ();
        nokvm_infobar.hide ();

        if (artifact != null) {
            App.app.delete_machine (artifact as Machine);
        }

        foreach (var child in customization_grid.get_children ())
            customization_grid.remove (child);
    }

    public override async void next () {
        if (artifact == null) {
            var wait = notify["artifact"].connect (() => {
                next.callback ();
            });
            yield;
            disconnect (wait);
        }

        // Let's apply all deferred changes in properties.
        foreach (var property in resource_properties) {
            property.flush ();
        }

        done (artifact);

        cancellable.reset ();
    }
}


[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-summary.ui")]
private class Boxes.WizardSummary: Gtk.Grid {
    public delegate void CustomizeFunc ();

    private int current_row;

    construct {
        current_row = 0;
    }

    public void add_property (string name, string? value) {
        if (value == null)
            return;

        var label_name = new Gtk.Label (name);
        label_name.get_style_context ().add_class ("dim-label");
        label_name.halign = Gtk.Align.END;
        attach (label_name, 0, current_row, 1, 1);

        var label_value = new Gtk.Label (value);
        label_value.set_ellipsize (Pango.EllipsizeMode.END);
        label_value.set_max_width_chars (32);
        label_value.halign = Gtk.Align.START;
        attach (label_value, 1, current_row, 1, 1);

        current_row += 1;
        show_all ();
    }

    public void clear () {
        foreach (var child in get_children ()) {
            remove (child);
        }

        current_row = 0;
    }
}
