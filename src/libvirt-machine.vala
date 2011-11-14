// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;
using Gtk;

private class Boxes.LibvirtMachine: Boxes.Machine {
    public GVir.Domain domain;
    public GVir.Connection connection;
    public DomainState state {
        get {
            try {
                return domain.get_info ().state;
            } catch (GLib.Error error) {
                return DomainState.NONE;
            }
        }
    }

    public override void disconnect_display () {
        if (_connect_display == false)
            return;

        _connect_display = false;
        app.display_page.remove_display ();
        update_display ();
    }

    private ulong started_id;
    public override void connect_display () {
        if (_connect_display == true)
            return;

        if (state != DomainState.RUNNING) {
            if (started_id != 0)
                return;

            if (state == DomainState.PAUSED) {
                started_id = domain.resumed.connect (() => {
                    domain.disconnect (started_id);
                    started_id = 0;
                    connect_display ();
                });
                try {
                    domain.resume ();
                } catch (GLib.Error error) {
                    warning (error.message);
                }
            } else {
                started_id = domain.started.connect (() => {
                    domain.disconnect (started_id);
                    started_id = 0;
                    connect_display ();
                });
                try {
                    domain.start (0);
                } catch (GLib.Error error) {
                    warning (error.message);
                }
            }
        }

        _connect_display = true;
        update_display ();
    }

    public LibvirtMachine (CollectionSource source, Boxes.App app,
                           GVir.Connection connection, GVir.Domain domain) {
        base (source, app, domain.get_name ());

        this.config = new DisplayConfig (source, domain.get_uuid ());
        this.connection = connection;
        this.domain = domain;

        set_screenshot_enable (true);
    }

    public override List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Pair<string, Widget>> ();

        switch (page) {
        case PropertiesPage.LOGIN:
            add_string_property (ref list, _("Virtualizer"), source.uri);
            add_string_property (ref list, _("URI"), display.uri);
            break;

        case PropertiesPage.DISPLAY:
            add_string_property (ref list, _("Protocol"), display.protocol);
            break;
        }

        list.concat (display.get_properties (page));

        return list;
    }

    private void update_display () {
        string type, port, socket, host;

        try {
            var xmldoc = domain.get_config (0).to_xml();
            type = extract_xpath (xmldoc, "string(/domain/devices/graphics/@type)", true);
            port = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@port)");
            socket = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@socket)");
            host = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@listen)");
        } catch (GLib.Error error) {
            warning (error.message);
            return;
        }

        if (display != null)
            display.disconnect_it ();

        if (host == null || host == "")
            host = "localhost";

        switch (type) {
        case "spice":
            display = new SpiceDisplay (config, host, int.parse (port));
            break;

        case "vnc":
            display = new VncDisplay (config, host, int.parse (port));
            break;

        default:
            warning ("unsupported display of type " + type);
            break;
        }
    }

    public override string get_screenshot_prefix () {
        return domain.get_uuid ();
    }

    public override bool is_running () {
        return state == DomainState.RUNNING;
    }

    public override async bool take_screenshot () throws GLib.Error {
        if (state != DomainState.RUNNING &&
            state != DomainState.PAUSED)
            return true;

        var stream = connection.get_stream (0);
        var file_name = get_screenshot_filename ();
        var file = File.new_for_path (file_name);
        var output_stream = yield file.replace_async (null, false, FileCreateFlags.REPLACE_DESTINATION);
        var input_stream = stream.get_input_stream ();
        domain.screenshot (stream, 0, 0);

        var buffer = new uint8[65535];
        ssize_t length = 0;
        do {
            length = yield input_stream.read_async (buffer);
            yield output_stream_write (output_stream, buffer[0:length]);
        } while (length > 0);

        return true;
    }

    public override void delete () {
        try {
            domain.stop (0);
            domain.delete (0);
        } catch (GLib.Error err) {
            warning (err.message);
        }
    }
}
