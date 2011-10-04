/*
 * Copyright (C) 2011 Red Hat, Inc.
 *
 * Authors: Marc-André Lureau <marcandre.lureau@gmail.com>
 *          Zeeshan Ali (Khattak) <zeeshanak@gnome.org>
 *
 * This file is part of GNOME Boxes.
 *
 * GNOME Boxes is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * GNOME Boxes is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

using Gtk;
using Spice;

public class Boxes.SpiceDisplay: Boxes.Display {
    private Session session;

    public SpiceDisplay (string host, int port) {
        this.session = new Session ();
        this.session.port = port.to_string ();
        this.session.host = host;
    }

    public override Gtk.Widget get_display (int n) throws Boxes.Error {
        var display = displays.lookup (n);

        if (display == null) {
            display = new Spice.Display (this.session, n);
        }

        if (display == null) {
            throw new Boxes.Error.INVALID ("invalid display");
        }

        return display;
    }

    public override void connect_it () {
        // FIXME: vala does't want to put this in ctor..
        this.session.channel_new.connect ((channel) => {
            if (channel is Spice.MainChannel)
                channel.channel_event.connect (this.main_event);

            if (channel is Spice.DisplayChannel) {
                var display = channel as DisplayChannel;

                show (display.channel_id);
                display.display_mark.connect ((mark) => { show (display.channel_id); });
            }
        });

        this.session.connect ();
    }

    public override void disconnect_it () {
        this.session.disconnect ();
    }

    private void main_event (ChannelEvent event) {
        if (ChannelEvent.CLOSED in event)
            disconnected ();
    }
}

