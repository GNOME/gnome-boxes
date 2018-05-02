// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.RemoteMachine: Boxes.Machine, Boxes.IPropertiesProvider {
    public override bool can_restart { get { return false; } }
    public override bool can_clone { get { return true; } }

    public RemoteMachine (CollectionSource source) throws Boxes.Error {
        if (source.source_type != "spice" &&
            source.source_type != "vnc")
            throw new Boxes.Error.INVALID ("source is not remote machine: %s", source.uri);

        base (source, source.name);

        // assume the remote is running for now
        state = MachineState.RUNNING;

        source.bind_property ("name", this, "name", BindingFlags.BIDIRECTIONAL);

        load_screenshot ();
        update_info ();

        notify["name"].connect (on_name_or_uri_changed);
        source.notify["uri"].connect (on_name_or_uri_changed);
    }

    private Display? create_display () throws Boxes.Error {
        var type = source.source_type;

        switch (type) {
        case "spice":
            return new SpiceDisplay.with_uri (this, config, source.uri);

        case "vnc":
            return new VncDisplay.with_uri (config, source.uri);

        default:
            throw new Boxes.Error.INVALID ("unsupported display of type " + type);
        }
    }

    public override async void connect_display (Machine.ConnectFlags flags) throws GLib.Error {
        config.access_last_time = get_real_time ();
        if (display == null) {
            display = create_display ();
            display.connect_it ();
        } else {
            if (!display.connected)
                display.connect_it ();

            show_display ();
            display.set_enable_audio (true);
        }
    }

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Boxes.Property> ();

        switch (page) {
        case PropertiesPage.GENERAL:
            var property = add_editable_string_property (ref list, _("_Name"), source.name);
            property.changed.connect ((property, name) => {
                this.name = name;
            });

            var name_property = property;
            notify["name"].connect (() => {
                name_property.text = name;
            });

            add_string_property (ref list, _("Protocol"), source.source_type.up ());
            if (is_connected) {
                add_string_property (ref list, _("URL"), source.uri);
            } else {
                property = add_editable_string_property (ref list, _("_URL"), source.uri);
                property.changed.connect ((property, uri) => {
                    source.uri = uri;
               });
            }

            break;
        }

        try {
            if (display == null)
                display = create_display ();

            list.concat (display.get_properties (page));
        } catch (Boxes.Error error) {
            warning (error.message);
        }

        return list;
    }

    public override void delete (bool by_user = true) {
        return_if_fail (by_user);

        base.delete ();

        source.delete ();
    }

    // FIXME: Implement this. We don't currently need it because we don't set any properties here that requires a
    //        restart and this method is currently used for that purpose only.
    public override void restart () {}

    public override async void clone () {
        var name = "Clone of %s".printf (source.name);
        var source = new CollectionSource (name, source.source_type, source.uri);
        source.save ();
        App.app.add_collection_source.begin (source);
    }

    private void update_info () {
        var uri = Xml.URI.parse (source.uri);
        if (uri == null || uri.server == name) // By default server is chosen as name
            return;

        info = uri.server;
    }

    private void on_name_or_uri_changed () {
        update_info ();
    }
}
