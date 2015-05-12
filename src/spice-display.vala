// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Spice;
using LibUSB;

private class Boxes.SpiceDisplay: Boxes.Display {
    public override string protocol { get { return "SPICE"; } }
    public override string uri { owned get { return session.uri; } }
    public GLib.ByteArray ca_cert { owned get { return session.ca; } set { session.ca = value; } }

    private weak Machine machine; // Weak ref for avoiding cyclic ref

    private Spice.Session session;
    private unowned Spice.GtkSession gtk_session;
    private unowned Spice.Audio audio;
    private ulong channel_new_id;
    private ulong channel_destroy_id;
    private BoxConfig.SyncProperty[] display_sync_properties;
    private BoxConfig.SyncProperty[] gtk_session_sync_properties;
    private bool closed;

    private void ui_state_changed () {
        // TODO: multi display
        if (machine.ui_state == UIState.DISPLAY) {
            // disable resize guest when minimizing guest widget
            var display = get_display (0) as Spice.Display;
            display.resize_guest = true;
        }
    }

    private string get_box_name () {
        //Translators: "Unknown" is a placeholder for a box name when it could not be determined
        return config.last_seen_name?? _("Unknown");
    }

    construct {
        gtk_session_sync_properties = {
            BoxConfig.SyncProperty () { name = "auto-clipboard", default_value = true },
        };

        need_password = false;
        session = new Session ();
        audio = Spice.Audio.get (session, null);
        gtk_session = GtkSession.get (session);
        try {
            var manager = UsbDeviceManager.get (session);

            manager.device_error.connect ( (dev, err) => {
                var device_description = dev.get_description ("%1$s %2$s");
                var box_name = get_box_name ();
                got_error (_("Redirection of USB device '%s' for '%s' failed").printf (device_description, box_name));
                debug ("Error connecting %s to %s: %s", device_description, box_name, err.message);
            });
        } catch (GLib.Error error) {
        }

        this.notify["config"].connect (() => {
            config.sync_properties (gtk_session, gtk_session_sync_properties);
        });
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

    public SpiceDisplay (Machine machine, BoxConfig config, string host, int port, int tls_port = 0, string? host_subject = null)
        requires (port != 0 || tls_port != 0) {
        this.machine = machine;
        machine.notify["ui-state"].connect (ui_state_changed);

        this.config = config;

        session.host = host;
        if (port != 0)
            session.port = port.to_string ();

        if (tls_port != 0)
            session.tls_port = tls_port.to_string ();

        // FIXME: together with newer oVirt, libgovirt should be able
        // to automatically provide the host subject when needed. Keep
        // this environment variable a while longer to be able to cope
        // with older oVirt versions.
        if (host_subject != null)
            session.cert_subject = host_subject;
        else
            session.cert_subject = GLib.Environment.get_variable ("BOXES_SPICE_HOST_SUBJECT");
    }

    public SpiceDisplay.with_uri (Machine machine, BoxConfig config, string uri) {
        this.machine = machine;
        machine.notify["ui-state"].connect (ui_state_changed);

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
            display.keyboard_grab.connect((status) => {
                keyboard_grabbed = status != 0;
            });
            config.sync_properties (this, display_sync_properties);
            display.scaling = true;

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

    public override void collect_logs (StringBuilder builder) {
        builder.append_printf ("URI: %s\n", uri);
        if (gtk_session != null) {
            builder.append_printf ("Auto clipboard sync: %s\n", gtk_session.auto_clipboard ? "yes" : "no");
        }
        if (main_channel != null) {
            builder.append_printf ("Spice-gtk version %s\n", Spice.util_get_version_string ());
            builder.append_printf ("Mouse mode: %s\n", main_channel.mouse_mode == 1 ? "server" : "client");
            builder.append_printf ("Agent: %s\n", main_channel.agent_connected ? "connected" : "disconnected");
        }

        try {
            var manager = UsbDeviceManager.get (session);
            var devs = manager.get_devices ();
            for (int i = 0; i < devs.length; i++) {
                var dev = devs[i];
                if (manager.is_device_connected (dev))
                    builder.append_printf ("USB device redirected: %s\n", dev.get_description ("%s %s %s at %d-%d"));
            }
        } catch (GLib.Error error) {
        }
    }

    public override void connect_it (Display.OpenFDFunc? open_fd = null) {
        // We only initiate connection once
        if (connected)
            return;
        connected = true;

        main_cleanup ();

        // FIXME: vala does't want to put this in constructor..
        if (channel_new_id == 0)
            channel_new_id = session.channel_new.connect ((channel) => {
                var id = channel.channel_id;

                if (open_fd != null)
                    channel.open_fd.connect (() => {
                        int fd;

                        fd = open_fd ();
                        channel.open_fd (fd);
                    });

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
        if (open_fd != null)
            session.open_fd (-1);
        else
            session.connect ();
    }

    public override void disconnect_it () {
        if (channel_new_id > 0) {
            (session as GLib.Object).disconnect (channel_new_id);
            channel_new_id = 0;
        }
        if (channel_destroy_id > 0) {
            (session as GLib.Object).disconnect (channel_destroy_id);
            channel_destroy_id = 0;
        }
        session.disconnect ();
        main_cleanup ();
    }

    private void main_event (ChannelEvent event) {
        switch (event) {
        case ChannelEvent.CLOSED:
            closed = true;
            disconnected (false);
            break;

        case ChannelEvent.ERROR_AUTH:
            need_password = true;
            break;

        case ChannelEvent.ERROR_CONNECT:
        case ChannelEvent.ERROR_TLS:
        case ChannelEvent.ERROR_LINK:
        case ChannelEvent.ERROR_IO:
            debug ("main SPICE channel error: %d", event);
            closed = true;
            disconnected (true);
            break;

        default:
            debug ("unhandled main SPICE channel event: %d", event);
            break;
        }
    }

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page, ref PropertyCreationFlag flags) {
        var list = new List<Boxes.Property> ();

        switch (page) {
        case PropertiesPage.GENERAL:
            var toggle = new Gtk.Switch ();
            gtk_session.bind_property ("auto-clipboard", toggle, "active",
                                       BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
            toggle.halign = Gtk.Align.START;
            add_property (ref list, _("Share Clipboard"), toggle);
            break;

        case PropertiesPage.DEVICES:
            if (PropertyCreationFlag.NO_USB in flags || !Config.HAVE_USBREDIR|| !connected)
                break;

            try {
                var manager = UsbDeviceManager.get (session);
                var devs = get_usb_devices (manager);

                if (devs.length <= 0)
                    return list;

                devs.sort ( (a, b) => {
                    string str_a = a.get_description ("    %1$s %2$s");
                    string str_b = b.get_description ("    %1$s %2$s");

                    return strcmp (str_a, str_b);
                });

                var frame = new Gtk.Frame (null);
                var listbox = new Gtk.ListBox ();
                listbox.hexpand = true;
                frame.add (listbox);

                for (int i = 0; i < devs.length; i++) {
                    var dev = devs[i];

                    var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                    hbox.margin_start = 12;
                    hbox.margin_end = 12;
                    hbox.margin_top = 6;
                    hbox.margin_bottom = 6;
                    var label = new Gtk.Label (dev.get_description ("%1$s %2$s"));
                    label.halign = Gtk.Align.START;
                    hbox.pack_start (label, true, true, 0);
                    var dev_toggle = new Gtk.Switch ();
                    dev_toggle.halign = Gtk.Align.END;
                    hbox.pack_start (dev_toggle, true, true, 0);
                    listbox.prepend (hbox);

                    dev_toggle.active = manager.is_device_connected (dev);

                    dev_toggle.notify["active"].connect ( () => {
                        if (dev_toggle.active) {
                            manager.connect_device_async.begin (dev, null, (obj, res) => {
                                try {
                                    manager.connect_device_async.end (res);
                                } catch (GLib.Error err) {
                                    dev_toggle.active = false;
                                    var device_desc = dev.get_description ("%1$s %2$s");
                                    var box_name = get_box_name ();
                                    var msg = _("Redirection of USB device '%s' for '%s' failed");
                                    got_error (msg.printf (device_desc, box_name));
                                    debug ("Error connecting %s to %s: %s",
                                           device_desc,
                                           box_name, err.message);
                                }
                            });
                        } else {
                            manager.disconnect_device (dev);
                        }
                    });
                }

                var usb_property = add_property (ref list, _("USB devices"), new Gtk.Label (""), frame);

                manager.device_added.connect ((manager, dev) => {
                    usb_property.refresh_properties ();
                });
                manager.device_removed.connect ((manager, dev) => {
                    usb_property.refresh_properties ();
                });
            } catch (GLib.Error error) {
            }
            break;
        }

        return list;
    }

    public override void send_keys (uint[] keyvals) {
        // TODO: multi display
        var display = get_display (0) as Spice.Display;

        display.send_keys (keyvals, DisplayKeyEvent.CLICK);
    }

    private GLib.GenericArray<UsbDevice> get_usb_devices (UsbDeviceManager manager) {
        GLib.GenericArray<UsbDevice> ret = new GLib.GenericArray<UsbDevice> ();
        var devs = manager.get_devices ();

        for (int i = 0; i < devs.length; i++) {
            var dev = devs[i];
            var libusb_dev = (LibUSB.Device) dev.get_libusb_device ();

            // The info about the device class, subclass and protocol can be in the device descriptor ...
            LibUSB.DeviceDescriptor desc;
            if (libusb_dev.get_device_descriptor (out desc) != 0)
                continue;

            if (is_usb_kbd_or_mouse (desc.bDeviceClass, desc.bDeviceSubClass, desc.bDeviceProtocol))
                continue;

            // ... or in one of the interfaces descriptors
            if (desc.bDeviceClass == LibUSB.ClassCode.PER_INTERFACE) {
                LibUSB.ConfigDescriptor config;
                if (libusb_dev.get_active_config_descriptor (out config) != 0)
                    continue;

                var kbd_or_mouse = false;
                for (int j = 0; j < config.@interface.length && !kbd_or_mouse; j++) {
                    for (int k = 0; k < config.@interface[j].altsetting.length && !kbd_or_mouse; k++) {
                        var class = config.@interface[j].altsetting[k].bInterfaceClass;
                        var subclass = config.@interface[j].altsetting[k].bInterfaceSubClass;
                        var protocol = config.@interface[j].altsetting[k].bInterfaceProtocol;

                        kbd_or_mouse = is_usb_kbd_or_mouse (class, subclass, protocol);
                    }
                }

                if (kbd_or_mouse)
                    continue;
            }

            ret.add (dev);
        }

        return ret;
    }

    private bool is_usb_kbd_or_mouse (uint8 class, uint8 subclass, uint8 protocol) {
        var ret = false;

        if (class == LibUSB.ClassCode.HID) {
            switch (subclass) {
            case 0x00: // None
                break;
            case 0x01: // BootInterface
               switch (protocol) {
               case 0x00: // None
                   break;
               case 0x01: // Keyboard
               case 0x02: // Mouse
                   ret = true;
                   break;
                default:
                    break;
               }
               break;
            default:
                break;
            }
        }

        return ret;
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
