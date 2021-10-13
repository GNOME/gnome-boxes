// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Vnc;

private class Boxes.VncDisplay: Boxes.Display {
    public override string protocol { get { return "VNC"; } }
    public override string? uri { owned get { return @"vnc://$host:$port"; } }
    private Vnc.Display display;
    private string host;
    private int port;
    private Gtk.Window window;
    private BoxConfig.SavedProperty[] saved_properties;

    construct {
        saved_properties = {
            BoxConfig.SavedProperty () { name = "read-only", default_value = false }
        };

        display = new Vnc.Display ();
        display.set_keyboard_grab (true);
        display.set_pointer_grab (true);
        display.set_force_size (false);
        display.set_scaling (true);

        set_enable_audio (true);

        // the VNC widget doesn't like not to have a realized window,
        // so we put it into a window temporarily
        window = new Gtk.Window ();
        window.add (display);
        display.realize ();

        display.vnc_initialized.connect (() => {
            show (0);
            access_start ();
        });
        display.vnc_disconnected.connect (() => {
            hide (0);
            access_finish ();

            disconnected (true);
        });

        display.size_allocate.connect (scale);
    }

    public VncDisplay (BoxConfig config, string host, int port) {
        this.config = config;

        this.host = host;
        this.port = port;

        config.save_properties (display, saved_properties);
    }

    public VncDisplay.with_uri (BoxConfig config, string _uri) throws Boxes.Error {
        this.config = config;

        var uri = Xml.URI.parse (_uri);

        if (uri.scheme != "vnc")
            throw new Boxes.Error.INVALID ("the URL is not vnc://");

        if (uri.server == null)
            throw new Boxes.Error.INVALID ("the URL is missing a server");

        this.host = uri.server;
        this.port = uri.port <= 0 ? 5900 : uri.port;

        config.save_properties (display, saved_properties);
    }

    public override Gtk.Widget get_display (int n) {
        window.remove (display);

        return display;
    }

    public override void set_enable_audio (bool enable) {
        var connection = display.get_connection ();
        if (!enable) {
            connection.audio_disable ();

            return;
        }

        connection.set_audio_format (new Vnc.AudioFormat () {
            frequency = 44100,
            nchannels = 2
        });
        connection.set_audio (new Vnc.AudioPulse ());
        connection.audio_enable ();
    }

    public override Gdk.Pixbuf? get_pixbuf (int n) throws Boxes.Error {
        return display.get_pixbuf ();
    }

    public override void connect_it (owned Display.OpenFDFunc? open_fd = null) throws GLib.Error {
        // We only initiate connection once
        if (connected)
            return;
        connected = true;

        if (open_fd != null) {
            var fd = open_fd ();
            display.open_fd_with_hostname (fd, host);
        } else
            display.open_host (host, port.to_string ());
    }

    public override void disconnect_it () {
        if (display.is_open ())
            display.close ();
    }

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Boxes.Property> ();

        switch (page) {
        case PropertiesPage.GENERAL:
            var toggle = new Gtk.Switch ();
            toggle.halign = Gtk.Align.START;
            display.bind_property ("read-only", toggle, "active",
                                   BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
            add_property (ref list, _("Read-only"), toggle);
            break;
        }

        return list;
    }

    public override void send_keys (uint[] keyvals) {
        display.send_keys (keyvals);
    }

    public void scale () {
        if (!display.is_open ())
            return;

        // Get the allocated size of the parent container
        Gtk.Allocation alloc;
        display.get_parent ().get_allocation (out alloc);

        double parent_aspect = (double) alloc.width / (double) alloc.height;
        double display_aspect = (double) display.get_width () / (double) display.get_height ();
        Gtk.Allocation scaled = alloc;
        if (parent_aspect > display_aspect) {
            scaled.width = (int) (alloc.height * display_aspect);
            scaled.x += (alloc.width - scaled.width) / 2;
        } else {
            scaled.height = (int) (alloc.width / display_aspect);
            scaled.y += (alloc.height - scaled.height) / 2;
        }

        display.size_allocate (scaled);
    }
}
