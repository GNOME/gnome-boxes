// This file is part of GNOME Boxes. License: LGPLv2
using Gtk;
using Spice;

private class Boxes.SpiceDisplay: Boxes.Display {
    private Session session;

    public SpiceDisplay (string host, int port) {
        session = new Session ();
        session.port = port.to_string ();
        session.host = host;
    }

    public override Gtk.Widget get_display (int n) throws Boxes.Error {
        var display = displays.lookup (n);

        if (display == null) {
            display = new Spice.Display (session, n);
        }

        if (display == null) {
            throw new Boxes.Error.INVALID ("invalid display");
        }

        return display;
    }

    public override void connect_it () {
        // FIXME: vala does't want to put this in ctor..
        session.channel_new.connect ((channel) => {
            if (channel is Spice.MainChannel)
                channel.channel_event.connect (main_event);

            if (channel is Spice.DisplayChannel) {
                var display = channel as DisplayChannel;

                show (display.channel_id);
                display.display_mark.connect ((mark) => { show (display.channel_id); });
            }
        });

        session.connect ();
    }

    public override void disconnect_it () {
        session.disconnect ();
    }

    private void main_event (ChannelEvent event) {
        if (ChannelEvent.CLOSED in event)
            disconnected ();
    }
}

