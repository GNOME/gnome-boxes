// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Vnc;

private class Boxes.VncDisplay: Boxes.Display {
    private Vnc.Display display;
    private string host;
    private int port;
    private Gtk.Window window;

    construct {
        need_password = false;

        display = new Vnc.Display ();
        display.set_keyboard_grab (true);
        display.set_pointer_grab (true);
        display.set_force_size (false);
        display.set_scaling (true);

        // the VNC widget doesn't like not to have a realized window,
        // so we put it into a window temporarily
        window = new Gtk.Window ();
        window.add (display);
        display.realize ();

        display.vnc_connected.connect (() => {
            show (0);
        });
        display.vnc_disconnected.connect (() => {
            hide (0);
        });
        display.vnc_initialized.connect (() => {
            debug ("initialized");
        });
        display.vnc_auth_failure.connect (() => {
            debug ("auth failure");
        });
        display.vnc_auth_unsupported.connect (() => {
            debug ("auth unsupported");
        });
        display.vnc_auth_credential.connect (() => {
            debug ("auth credentials");
        });
    }

    public VncDisplay (string host, int port) {
        this.host = host;
        this.port = port;
    }

    public VncDisplay.with_uri (string _uri) throws Boxes.Error {
        var uri = Xml.URI.parse (_uri);

        if (uri.scheme != "vnc")
            throw new Boxes.Error.INVALID ("the URI is not vnc://");

        if (uri.server == null)
            throw new Boxes.Error.INVALID ("the URI is missing a server");

        this.host = uri.server;
        this.port = uri.port == -1 ? 5900 : uri.port;
    }

    public override Gtk.Widget? get_display (int n) throws Boxes.Error {
        window.remove (display);
        return display;
    }

    public override void connect_it () {
        display.open_host (host, port.to_string ());
    }

    public override void disconnect_it () {
    }
}
