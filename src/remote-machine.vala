// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.RemoteMachine: Boxes.Machine, Boxes.IPropertiesProvider {

    public RemoteMachine (CollectionSource source) {
        base (source, source.name);

        // assume the remote is running for now
        state = MachineState.RUNNING;

        config = new DisplayConfig (source);
        source.bind_property ("name", this, "name", BindingFlags.DEFAULT);

        load_screenshot ();
    }

    public override void connect_display () {
        if (display != null)
            return;

        try {
            if (source.source_type == "spice")
                display = new SpiceDisplay.with_uri (config, source.uri);
            else if (source.source_type == "vnc")
                display = new VncDisplay.with_uri (config, source.uri);

            display.connect_it ();
        } catch (GLib.Error error) {
            warning (error.message);
        }
    }

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Boxes.Property> ();

        switch (page) {
        case PropertiesPage.LOGIN:
            add_string_property (ref list, _("Name"), source.name, (property, name) => {
                source.name = name;
            });
            add_string_property (ref list, _("URI"), source.uri);
            break;

        case PropertiesPage.DISPLAY:
            add_string_property (ref list, _("Protocol"), source.source_type.up ());
            break;
        }

        list.concat (display.get_properties (page));

        return list;
    }

    public override string get_screenshot_prefix () {
        return source.filename;
    }

    public override void delete (bool by_user = true) {
        return_if_fail (by_user);

        source.delete ();
    }
}
