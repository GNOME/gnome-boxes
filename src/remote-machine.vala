// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.RemoteMachine: Boxes.Machine, Boxes.IPropertiesProvider {

    public RemoteMachine (CollectionSource source) throws Boxes.Error {
        if (source.source_type != "spice" &&
            source.source_type != "vnc")
            throw new Boxes.Error.INVALID ("source is not remote machine: %s", source.uri);

        base (source, source.name);

        // assume the remote is running for now
        state = MachineState.RUNNING;

        create_display_config ();
        source.bind_property ("name", this, "name", BindingFlags.DEFAULT);

        load_screenshot ();
    }

    private Display? create_display () throws Boxes.Error {
        var type = source.source_type;

        switch (type) {
        case "spice":
            return new SpiceDisplay.with_uri (config, source.uri);

        case "vnc":
            return new VncDisplay.with_uri (config, source.uri);

        default:
            throw new Boxes.Error.INVALID ("unsupported display of type " + type);
        }
    }

    public override async void connect_display (Machine.ConnectFlags flags) throws GLib.Error {
        if (display == null) {
            display = create_display ();
            display.connect_it ();
        } else {
            show_display ();
            display.set_enable_audio (true);
        }
    }

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page, ref PropertyCreationFlag flags) {
        var list = new List<Boxes.Property> ();

        switch (page) {
        case PropertiesPage.LOGIN:
            var property = add_string_property (ref list, _("Name"), source.name);
            property.editable = true;
            property.changed.connect ((property, name) => {
                source.name = name;
                return true;
            });
            add_string_property (ref list, _("URI"), source.uri);
            break;

        case PropertiesPage.DISPLAY:
            add_string_property (ref list, _("Protocol"), source.source_type.up ());
            break;
        }

        try {
            if (display == null)
                display = create_display ();

            list.concat (display.get_properties (page, ref flags));
        } catch (Boxes.Error error) {
            warning (error.message);
        }

        return list;
    }

    public override void delete (bool by_user = true) {
        return_if_fail (by_user);

        source.delete ();
    }
}
