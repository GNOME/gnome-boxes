// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.RemoteMachine: Boxes.Machine, Boxes.IPropertiesProvider {

    public RemoteMachine (CollectionSource source, Boxes.App app) {
        base (source, app, source.name);

        config = new DisplayConfig (source);
        source.bind_property ("name", this, "name", BindingFlags.DEFAULT);
        update_screenshot.begin ();
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

    public override string get_screenshot_filename (string ext = "jpg") {
        return base.get_screenshot_filename (ext);
    }

    public override void disconnect_display () {
        if (display == null)
            return;

        app.display_page.remove_display ();

        if (display != null) {
            try {
                var pixbuf = display.get_pixbuf (0);
                if (pixbuf != null) {
                    pixbuf.save (get_screenshot_filename (), "jpeg");
                    update_screenshot ();
                }
            } catch (GLib.Error err) {
                warning (err.message);
            }

            display.disconnect_it ();
            display = null;
        }
    }

    public override List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Pair<string, Widget>> ();

        switch (page) {
        case PropertiesPage.LOGIN:
            add_string_property (ref list, _("Name"), source.name, (name) => {
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

    public override bool is_running () {
        // assume the remote is running for now
        return true;
    }

    public override void delete (bool by_user = true) {
        return_if_fail (by_user);

        source.delete ();
    }
}
