// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/machine-config-editor.ui")]
private class Boxes.MachineConfigEditor: Gtk.ScrolledWindow {
    private const string BOXES_NS_URI = "https://wiki.gnome.org/Apps/Boxes/edited";
    private const string MANUALLY_EDITED_XML = "<edited>%u</edited>";

    [GtkChild]
    private Gtk.SourceView view;

    private LibvirtMachine machine;

    public void setup (LibvirtMachine machine) {
        this.machine = machine;

        var buffer = new Gtk.SourceBuffer (null);
        buffer.language = Gtk.SourceLanguageManager.get_default ().get_language ("xml");
        view.buffer = buffer;

        buffer.set_text (machine.domain_config.to_xml ());
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
            warning ("Failed to save custom XML: %s", error.message);
        }
    }

    public async void save () {
        var xml = view.buffer.text;
        if (machine.domain_config.to_xml () == xml) {
            debug ("Nothing changed in the VM configuration");

            return;
        }

        var snapshot_timestamp = yield create_snapshot ();
        if (snapshot_timestamp == 0) {
            warning ("Failed to save changes!");

            return;
        }

        GVirConfig.Domain? custom_config = null;
        try {
            custom_config = new GVirConfig.Domain.from_xml (xml);
        } catch (GLib.Error error) {
            warning ("Failed to save changes!\n");
        }

        add_metadata (custom_config, snapshot_timestamp);

        try {
            machine.domain.set_config (custom_config);
        } catch (GLib.Error error) {
            warning ("Failed to save custom VM configuration: %s", error.message);
            var msg = _("Boxes failed to save VM configuration changes: %s");
            App.app.main_window.notificationbar.display_error (msg);

            return;
        }

        if (machine.is_running) {
            var message = _("Changes require restart of “%s”.").printf (machine.name);
            App.app.main_window.notificationbar.display_for_action (message, _("_Restart"), () => {
                machine.restart ();
            });
        }
    }

}
