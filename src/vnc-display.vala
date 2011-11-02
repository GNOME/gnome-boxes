// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Vnc;

private class Boxes.VncDisplay: Boxes.Display {
    public override string protocol { get { return "VNC"; } }
    public override string uri { owned get { return @"vnc://$host:$port"; } }

    private Vnc.Display display;
    private string host;
    private int port;
    private Gtk.Window window;
    private Display.SavedProperty[] saved_properties;

    construct {
        saved_properties = {
            SavedProperty () { name = "read-only", default_value = false }
        };
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

        display.vnc_initialized.connect (() => {
            show (0);
        });
        display.vnc_disconnected.connect (() => {
            hide (0);
        });

        display.vnc_auth_failure.connect (() => {
            debug ("auth failure");
        });
        display.vnc_auth_unsupported.connect (() => {
            debug ("auth unsupported");
        });

        display.vnc_auth_credential.connect ((vnc, creds) => {
            foreach (var cred in creds) {
                var credential = cred as DisplayCredential;

                switch (credential) {
                case DisplayCredential.USERNAME:
                    need_username = true;
                    break;

                case DisplayCredential.PASSWORD:
                    need_password = true;
                    break;

                case DisplayCredential.CLIENTNAME:
                    break;

                default:
                    debug ("Unsupported credential: %s".printf (credential.to_string ()));
                    break;
                }
            }

            display.close ();
        });
    }

    public VncDisplay (string host, int port) {
        this.host = host;
        this.port = port;
    }

    public VncDisplay.with_uri (CollectionSource source, string _uri) throws Boxes.Error {
        this.source = source;
        sync_source_with_display (display, saved_properties);

        var uri = Xml.URI.parse (_uri);

        if (uri.scheme != "vnc")
            throw new Boxes.Error.INVALID ("the URI is not vnc://");

        if (uri.server == null)
            throw new Boxes.Error.INVALID ("the URI is missing a server");

        this.host = uri.server;
        this.port = uri.port <= 0 ? 5900 : uri.port;
    }

    public override Gtk.Widget? get_display (int n) throws Boxes.Error {
        window.remove (display);

        return display;
    }

    public override Gdk.Pixbuf get_pixbuf (int n) throws Boxes.Error {
        return display.get_pixbuf ();
    }

    public override void connect_it () {
        // FIXME: we ignore return value which seems to be inconsistent
        display.set_credential (DisplayCredential.USERNAME, username);
        display.set_credential (DisplayCredential.PASSWORD, password);
        display.set_credential (DisplayCredential.CLIENTNAME, "boxes");

        display.open_host (host, port.to_string ());
    }

    public override void disconnect_it () {
        if (display.is_open ())
            display.close ();
    }

    public override List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Pair<string, Widget>> ();

        switch (page) {
        case PropertiesPage.DISPLAY:
            var toggle = new Gtk.Switch ();
            display.bind_property ("read-only", toggle, "active",
                                   BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
            add_property (ref list, _("Read-only"), toggle);
            break;
        }

        return list;
    }
}
