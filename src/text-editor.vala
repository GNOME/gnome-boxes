// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/text-editor.ui")]
private class Boxes.TextEditor: Gtk.ScrolledWindow {
    private const string BOXES_NS = "boxes";
    private const string BOXES_NS_URI = "https://wiki.gnome.org/Apps/Boxes/edited";
    private const string MANUALLY_EDITED_XML = "<edited>%u</edited>";
    private const string FILE_SUFFIX = ".original.xml";

    [GtkChild]
    private Gtk.SourceView view;

    private LibvirtMachine machine;

    public void setup (LibvirtMachine machine) {
        this.machine = machine;

        var buffer = new Gtk.SourceBuffer (null);
        buffer.language = Gtk.SourceLanguageManager.get_default ().get_language ("xml");
        view.buffer = buffer;

        try {
            var config = machine.domain.get_config (GVir.DomainXMLFlags.NONE);
            buffer.set_text (config.to_xml ());
        } catch (GLib.Error error) {
            warning ("Failed to load machine configuration: %s", error.message);
        }
    }

    public async void save () {
        GVirConfig.Domain? config = null;
        try {
            config = machine.domain.get_config (GVir.DomainXMLFlags.NONE);
        } catch (GLib.Error error) {
            warning ("Failed to load machine configuration: %s", error.message);
            return;
        }

        var saved = yield save_original_config (config);

        var xml = view.buffer.text;
        GVirConfig.Domain? custom_config = null;
        try {
            custom_config = new GVirConfig.Domain.from_xml (xml);
        } catch (GLib.Error error) {
            warning ("Failed to save changes!\n");
        }

        add_metadata (custom_config);

        machine.domain.set_config (custom_config);
    }

    private void add_metadata (GVirConfig.Domain config) {
        string edited_xml = MANUALLY_EDITED_XML.printf (1);

        try {
            config.set_custom_xml (edited_xml, "edited", BOXES_NS_URI); 
        } catch (GLib.Error error) {
            warning ("Failed to save custom XML: %s", error.message);
        }
    }

    private async bool save_original_config (GVirConfig.Domain config) {
        var old_config_path = get_user_pkgconfig (config.get_name () + FILE_SUFFIX);

        return FileUtils.set_contents (old_config_path, config.to_xml (), -1);
    }

    public async void revert_to_original () {
        var original_config_path = get_user_pkgconfig (machine.domain_config.get_name () + FILE_SUFFIX);

        string data;
        FileUtils.get_contents (original_config_path, out data);
        if (data == null) {
            warning ("Failed to load original config");
            return;
        }

        try {
            var config = new GVirConfig.Domain.from_xml (data);
            machine.domain.set_config (config);

            view.buffer.text = data;
        } catch (GLib.Error error) {
            warning ("Failed to load old configurations %s", error.message);
        }
    }
}
