// This file is part of GNOME Boxes. License: LGPLv2
using Gtk;
using Spice;

private class Boxes.SpiceDisplay: Boxes.Display {
    private Session session;
    private ulong channel_new_id;

    public SpiceDisplay (string host, int port) {
        session = new Session ();
        session.port = port.to_string ();
        session.host = host;
        need_password = false;
    }

    public override Gtk.Widget get_display (int n) throws Boxes.Error {
        var display = displays.lookup (n) as Spice.Display;

        if (display == null) {
            display = new Spice.Display (session, n);
            display.resize_guest = true;
            display.scaling = true;
        }

        if (display == null) {
            throw new Boxes.Error.INVALID ("invalid display");
        }

        return display;
    }

    public override void connect_it () {
        // FIXME: vala does't want to put this in ctor..
        if (channel_new_id == 0) {
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
        }

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
}
