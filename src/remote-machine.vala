// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.RemoteMachine: Boxes.Machine, Boxes.IPropertiesProvider {

    public RemoteMachine (CollectionSource source) {
        base (source, source.name);

        // assume the remote is running for now
        state = MachineState.RUNNING;

        create_display_config ();
        source.bind_property ("name", this, "name", BindingFlags.DEFAULT);

        load_screenshot ();
    }

    public override async void connect_display () throws GLib.Error {
        if (display != null)
            return;

        if (source.source_type == "spice")
            display = new SpiceDisplay.with_uri (config, source.uri);
        else if (source.source_type == "vnc")
            display = new VncDisplay.with_uri (config, source.uri);

        display.connect_it ();
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

    public override void delete (bool by_user = true) {
        return_if_fail (by_user);

        source.delete ();
    }
}
