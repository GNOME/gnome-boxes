// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/machine-config-editor.ui")]
private class Boxes.MachineConfigEditor: Gtk.ScrolledWindow {
    private const string BOXES_NS_URI = "https://wiki.gnome.org/Apps/Boxes/edited";
    private const string MANUALLY_EDITED_XML = "<edited>%u</edited>";

    private Gtk.Button apply_config_button;
    [GtkChild]
    private Gtk.SourceView view;

    private LibvirtMachine machine;
    private string domain_xml;

    public void setup (LibvirtMachine machine, Gtk.Button apply_config_button) {
        this.machine = machine;
        this.apply_config_button = apply_config_button;

        var buffer = new Gtk.SourceBuffer (null);
        buffer.language = Gtk.SourceLanguageManager.get_default ().get_language ("xml");
        view.buffer = buffer;

        domain_xml = machine.domain_config.to_xml ();
        buffer.set_text (domain_xml);

        buffer.changed.connect (on_config_changed);
    }

    private async long create_snapshot () {
        long snapshot_timestamp = 0;
        try {
            var snapshot = yield machine.create_snapshot (_("Configuration modified "));
            try {
                var config = snapshot.get_config (0);
                snapshot_timestamp = config.get_creation_time ();
            } catch (GLib.Error error) {
                warning ("Failed to obtain snapshot configuration: %s", error.message);
            }
        } catch (GLib.Error error) {
            warning ("Failed to create snapshot: %s", error.message);
        }

        return snapshot_timestamp;
    }

    private void add_metadata (GVirConfig.Domain config, long snapshot_timestamp) {
        string edited_xml = MANUALLY_EDITED_XML.printf (snapshot_timestamp);

        try {
            config.set_custom_xml (edited_xml, "edited", BOXES_NS_URI);
        } catch (GLib.Error error) {
            warning ("Failed to apply custom XML: %s", error.message);
        }
    }

    public async void apply () {
        var xml = view.buffer.text;
        if (machine.domain_config.to_xml () == xml) {
            debug ("Nothing changed in the VM configuration");

            return;
        }

        var snapshot_timestamp = yield create_snapshot ();
        if (snapshot_timestamp == 0) {
            warning ("Failed to apply changes!");

            return;
        }

        GVirConfig.Domain? custom_config = null;
        try {
            custom_config = new GVirConfig.Domain.from_xml (xml);
        } catch (GLib.Error error) {
            warning ("Failed to apply changes!\n");
        }

        add_metadata (custom_config, snapshot_timestamp);

        try {
            machine.domain.set_config (custom_config);
            domain_xml = custom_config.to_xml ();
        } catch (GLib.Error error) {
            warning ("Failed to apply custom VM configuration: %s", error.message);
            var msg = _("Boxes failed to apply VM configuration changes: %s");
            App.app.main_window.notificationbar.display_error (msg);

            return;
        }

        if (machine.is_running) {
            var message = _("Changes require restart of “%s”.").printf (machine.name);
            App.app.main_window.notificationbar.display_for_action (message, _("_Restart"), () => {
                machine.restart ();
            });
        }

        setup (machine, apply_config_button);
    }

    private void on_config_changed () {
        var config_changed = (view.buffer.text != domain_xml);
        apply_config_button.sensitive = config_changed;
    }
}
