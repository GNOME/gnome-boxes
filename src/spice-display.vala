// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Spice;

private class Boxes.SpiceDisplay: Boxes.Display {
    public override string protocol { get { return "SPICE"; } }
    public override string uri { owned get { return session.uri; } }

    private Spice.Session session;
    private unowned Spice.GtkSession gtk_session;
    private unowned Spice.Audio audio;
    private ulong channel_new_id;
    private ulong channel_destroy_id;
    private BoxConfig.SyncProperty[] display_sync_properties;
    private BoxConfig.SyncProperty[] gtk_session_sync_properties;
    private bool connected;
    private bool closed;

    public bool resize_guest { get; set; }
    private void ui_state_changed () {
        // TODO: multi display
        if (App.app.ui_state == UIState.PROPERTIES ||
            App.app.ui_state == UIState.DISPLAY) {
            // disable resize guest when minimizing guest widget
            var display = get_display (0) as Spice.Display;
            display.resize_guest = App.app.ui_state == UIState.DISPLAY ? resize_guest : false;
        }
    }

    construct {
        display_sync_properties = {
            BoxConfig.SyncProperty () { name = "resize-guest", default_value = true }
        };

        gtk_session_sync_properties = {
            BoxConfig.SyncProperty () { name = "auto-clipboard", default_value = true },
            BoxConfig.SyncProperty () { name = "auto-usbredir", default_value = false }
        };

        need_password = false;
        session = new Session ();
        audio = Spice.Audio.get (session, null);
        gtk_session = GtkSession.get (session);

        this.notify["config"].connect (() => {
            config.sync_properties (gtk_session, gtk_session_sync_properties);
        });

        App.app.notify["ui-state"].connect (ui_state_changed);
    }

    Spice.MainChannel? main_channel;
    ulong main_event_id;
    ulong main_mouse_mode_id;

    private void main_cleanup () {
        if (main_channel == null)
            return;

        var o = main_channel as Object;
        o.disconnect (main_event_id);
        main_event_id = 0;
        o.disconnect (main_mouse_mode_id);
        main_mouse_mode_id = 0;
        main_channel = null;
    }

    ~SpiceDisplay () {
        main_cleanup ();
    }

    public SpiceDisplay (BoxConfig config, string host, int port) {
        this.config = config;

        session.port = port.to_string ();
        session.host = host;
    }

    public SpiceDisplay.with_uri (BoxConfig config, string uri) {
        this.config = config;

        session.uri = uri;
    }

    public override Gtk.Widget get_display (int n) {
        var display = displays.lookup (n) as Spice.Display;

        if (display == null) {
            display = new Spice.Display (session, n);

            display.mouse_grab.connect((status) => {
                mouse_grabbed = status != 0;
            });
            config.sync_properties (this, display_sync_properties);
            display.scaling = true;
            if (display.get_class ().find_property ("only-downscale") != null)
                display.set ("only-downscale", true);

            displays.replace (n, display);
        }

        return display;
    }

    private bool has_usb_device_connected () {
        try {
            var manager = UsbDeviceManager.get (session);
            var devs = manager.get_devices ();
            for (int i = 0; i < devs.length; i++) {
                var dev = devs[i];
                if (manager.is_device_connected (dev))
                    return true;
            }
        } catch (GLib.Error error) {
        }
        return false;
    }

    public override bool should_keep_alive () {
        return !closed && has_usb_device_connected ();
    }

    public override void set_enable_audio (bool enable) {
        session.enable_audio = enable;
    }

    public override void set_enable_inputs (Gtk.Widget widget, bool enable) {
        (widget as Spice.Display).disable_inputs = !enable;
    }

    public override Gdk.Pixbuf? get_pixbuf (int n) {
        var display = get_display (n) as Spice.Display;

        if (!display.ready)
            return null;

        return display.get_pixbuf ();
    }

    public override void connect_it () {
        // We only initiate connection once
        if (connected)
            return;
        connected = true;

        main_cleanup ();

        // FIXME: vala does't want to put this in ctor..
        if (channel_new_id == 0)
            channel_new_id = session.channel_new.connect ((channel) => {
                var id = channel.channel_id;

                if (channel is Spice.MainChannel) {
                    main_channel = channel as Spice.MainChannel;
                    main_event_id = main_channel.channel_event.connect (main_event);
                    main_mouse_mode_id = main_channel.notify["mouse-mode"].connect(() => {
                        can_grab_mouse = main_channel.mouse_mode != 2;
                    });
                    can_grab_mouse = main_channel.mouse_mode != 2;
                }

                if (channel is Spice.DisplayChannel) {
                    if (id != 0)
                        return;

                    access_start ();
                    var display = get_display (id) as Spice.Display;
                    display.notify["ready"].connect (() => {
                        if (display.ready)
                            show (display.channel_id);
                        else
                            hide (display.channel_id);
                    });
                }
            });

        if (channel_destroy_id == 0)
            channel_destroy_id = session.channel_destroy.connect ((channel) => {
                if (channel is Spice.DisplayChannel) {
                    var display = channel as DisplayChannel;
                    hide (display.channel_id);
                    access_finish ();
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
            closed = true;
            disconnected ();
            break;

        case ChannelEvent.ERROR_AUTH:
            need_password = true;
            break;

        default:
            break;
        }
    }

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page, PropertyCreationFlag flags) {
        var list = new List<Boxes.Property> ();

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
            if (!(PropertyCreationFlag.NO_USB in flags)) {
                var toggle = new Gtk.Switch ();
                gtk_session.bind_property ("auto-usbredir", toggle, "active",
                                           BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
                toggle.halign =  Gtk.Align.START;
                add_property (ref list, _("Redirect new USB devices"), toggle);
            }
            break;
        }

        return list;
    }
}

// FIXME: this kind of function should be part of spice-gtk
static void spice_validate_uri (string uri_as_text,
                                out int? port = null,
                                out int? tls_port = null) throws Boxes.Error {
    var uri = Xml.URI.parse (uri_as_text);

    if (uri == null)
        throw new Boxes.Error.INVALID (_("Invalid URI"));

    tls_port = 0;
    port = uri.port;
    var query_str = uri.query_raw ?? uri.query;

    if (query_str != null) {
        var query = new Boxes.Query (query_str);
        if (query.get ("port") != null) {
            if (port > 0)
                throw new Boxes.Error.INVALID (_("The port must be specified once"));
            port = int.parse (query.get ("port"));
        }

        if (query.get ("tls-port") != null)
            tls_port = int.parse (query.get ("tls-port"));
    }

    if (port <= 0 && tls_port <= 0)
        throw new Boxes.Error.INVALID (_("Missing port in Spice URI"));
}
