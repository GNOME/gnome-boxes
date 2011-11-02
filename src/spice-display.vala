// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Spice;

private class Boxes.SpiceDisplay: Boxes.Display, Boxes.IProperties {
    public override string protocol { get { return "SPICE"; } }
    public override string uri { owned get { return session.uri; } }

    private Session session;
    private unowned GtkSession gtk_session;
    private ulong channel_new_id;
    private ulong channel_destroy_id;

    construct {
        need_password = false;
    }

    public SpiceDisplay (string host, int port) {
        session = new Session ();
        session.port = port.to_string ();
        session.host = host;
        gtk_session = GtkSession.get (session);
    }

    public SpiceDisplay.with_uri (string uri) {
        session = new Session ();
        session.uri = uri;
    }

    public override Gtk.Widget? get_display (int n) throws Boxes.Error {
        var display = displays.lookup (n) as Spice.Display;

        if (display == null) {
            display = new Spice.Display (session, n);

            if (display == null)
                throw new Boxes.Error.INVALID ("invalid display");

            display.resize_guest = true;
            display.scaling = true;

            displays.replace (n, display);
        }

        return display;
    }

    public override Gdk.Pixbuf get_pixbuf (int n) throws Boxes.Error {
        return (get_display (n) as Spice.Display).get_pixbuf ();
    }

    public override void connect_it () {
        // FIXME: vala does't want to put this in ctor..
        if (channel_new_id == 0)
            channel_new_id = session.channel_new.connect ((channel) => {
                if (channel is Spice.MainChannel)
                    channel.channel_event.connect (main_event);

                if (channel is Spice.DisplayChannel) {
                    var display = channel as DisplayChannel;

                    // FIXME: should show only when mark received? not reliable yet:
                    show (display.channel_id);
                    // display.display_mark.connect ((mark) => { show (display.channel_id); });
                }
            });

        if (channel_destroy_id == 0)
            channel_destroy_id = session.channel_destroy.connect ((channel) => {
                if (channel is Spice.DisplayChannel) {
                    var display = channel as DisplayChannel;
                    hide (display.channel_id);
                }
            });

        session.password = password;
        session.connect ();
    }

    public override void disconnect_it () {
        session.disconnect ();
    }

    private void main_event (ChannelEvent event) {
        switch (event) {
        case ChannelEvent.CLOSED:
            disconnected ();
            break;

        case ChannelEvent.ERROR_AUTH:
            need_password = true;
            break;

        default:
            break;
        }
    }

    public override List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Pair<string, Widget>> ();

        switch (page) {
        case PropertiesPage.DISPLAY:
            var toggle = new Gtk.Switch ();
            gtk_session.bind_property ("auto-clipboard", toggle, "active",
                                       BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
            add_property (ref list, _("Share clipboard"), toggle);

            try {
                toggle = new Gtk.Switch ();
                var display = get_display (0);
                display.bind_property ("resize-guest", toggle, "active",
                                       BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
                add_property (ref list, _("Resize guest"), toggle);
            } catch (Boxes.Error error) {
                warning (error.message);
            }
            break;

        case PropertiesPage.DEVICES:
            var toggle = new Gtk.Switch ();
            gtk_session.bind_property ("auto-usbredir", toggle, "active",
                                       BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
            add_property (ref list, _("USB redirection"), toggle);
            break;
        }

        return list;
    }
}
