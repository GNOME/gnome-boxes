using Gtk;
using Spice;

class Boxes.SpiceDisplay: Boxes.Display {
    Spice.Session session;

    public SpiceDisplay (string host, int port) {
        session = new Spice.Session ();
        session.port = port.to_string ();
        session.host = host;
    }

    public override Gtk.Widget get_display (int n)  throws Boxes.Error {
        var display = displays.lookup (n);

        if (display == null) {
            display = new Spice.Display (session, n);
        }
        if (display == null) {
            throw new Boxes.Error.INVALID ("invalid display");
        }

        return display;
    }

    private void main_event (ChannelEvent event) {
        if (ChannelEvent.CLOSED in event)
            disconnected ();
    }

    public override void connect_it () {
        // FIXME: vala does't want to put this in ctor..
        session.channel_new.connect ( (channel) => {
                if (channel is Spice.MainChannel) {
                    channel.channel_event.connect (main_event);
                }
                if (channel is Spice.DisplayChannel) {
                    var d = channel as DisplayChannel;
                    show (d.channel_id);
                    d.display_mark.connect ( (mark) => {
                            show (d.channel_id);
                        });
                }
            });

        session.connect ();
    }

    public override void disconnect_it () {
        session.disconnect ();
    }
}

