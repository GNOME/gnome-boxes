// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Spice;

private class Boxes.SpiceDisplay: Boxes.Display, Boxes.IPropertiesProvider {
    public override string protocol { get { return "SPICE"; } }
    public override string uri { owned get { return session.uri; } }

    private Spice.Session session;
    private unowned Spice.GtkSession gtk_session;
    private unowned Spice.Audio audio;
    private ulong channel_new_id;
    private ulong channel_destroy_id;
    private Display.SavedProperty[] display_saved_properties;
    private Display.SavedProperty[] gtk_session_saved_properties;

    public bool resize_guest { get; set; }
    private void ui_state_changed () {
        // TODO: multi display
        try {
            var display = get_display (0) as Spice.Display;
            if (App.app.ui_state == UIState.PROPERTIES) {
                // disable resize guest when minimizing guest widget
                display.resize_guest = false;
            } else if (App.app.ui_state == UIState.DISPLAY) {
                display.resize_guest = resize_guest;
            }
        } catch (Boxes.Error error) {
        }
    }

    construct {
        display_saved_properties = {
            SavedProperty () { name = "resize-guest", default_value = true }
        };

        gtk_session_saved_properties = {
            SavedProperty () { name = "auto-clipboard", default_value = true },
            SavedProperty () { name = "auto-usbredir", default_value = false }
        };

        need_password = false;
        session = new Session ();
        audio = Spice.Audio.get (session, null);
        gtk_session = GtkSession.get (session);

        this.notify["config"].connect (() => {
            sync_config_with_display (gtk_session, gtk_session_saved_properties);
        });

        App.app.notify["ui-state"].connect (ui_state_changed);
    }

    public SpiceDisplay (DisplayConfig config, string host, int port) {
        this.config = config;

        session.port = port.to_string ();
        session.host = host;
    }

    public SpiceDisplay.with_uri (DisplayConfig config, string uri) {
        this.config = config;

        session.uri = uri;
    }

    public override Gtk.Widget get_display (int n) throws Boxes.Error {
        var display = displays.lookup (n) as Spice.Display;

        if (display == null) {
            display = new Spice.Display (session, n);

            if (display == null)
                throw new Boxes.Error.INVALID ("invalid display");

            display.mouse_grab.connect((status) => {
                mouse_grabbed = status != 0;
            });
            sync_config_with_display (this, display_saved_properties);
            display.scaling = true;

            displays.replace (n, display);
        }

        return display;
    }

    public override void set_enable_inputs (Gtk.Widget widget, bool enable) {
        (widget as Spice.Display).disable_inputs = !enable;
    }

    public override Gdk.Pixbuf? get_pixbuf (int n) throws Boxes.Error {
        return (get_display (n) as Spice.Display).get_pixbuf ();
    }

    public override void connect_it () {
        // FIXME: vala does't want to put this in ctor..
        if (channel_new_id == 0)
            channel_new_id = session.channel_new.connect ((channel) => {
                if (channel is Spice.MainChannel) {
                    var main = channel as Spice.MainChannel;
                    main.channel_event.connect (main_event);
                    main.notify["mouse-mode"].connect(() => {
                        can_grab_mouse = main.mouse_mode != 2;
                    });
                    can_grab_mouse = main.mouse_mode != 2;
                }

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
            toggle.halign = Gtk.Align.START;
            add_property (ref list, _("Share clipboard"), toggle);

            toggle = new Gtk.Switch ();
            this.bind_property ("resize-guest", toggle, "active",
                                BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
            toggle.halign = Gtk.Align.START;
            add_property (ref list, _("Resize guest"), toggle);
            break;

        case PropertiesPage.DEVICES:
            var toggle = new Gtk.Switch ();
            gtk_session.bind_property ("auto-usbredir", toggle, "active",
                                       BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
            toggle.halign = Gtk.Align.START;
            add_property (ref list, _("USB redirection"), toggle);
            break;
        }

        return list;
    }
}
