// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Spice;
using LibUSB;

private class Boxes.SpiceDisplay: Boxes.Display {
    public override string protocol { get { return "SPICE"; } }
    public override string? uri {
        owned get {
            if (session.port == null && session.tls_port == null)
                return null;

            return session.uri;
        }
    }
    public override bool can_transfer_files { get { return main_channel.agent_connected; } }
    public GLib.ByteArray ca_cert { owned get { return session.ca; } set { session.ca = value; } }

    private weak Machine machine; // Weak ref for avoiding cyclic ref

    private Spice.Session session;
    private unowned Spice.GtkSession gtk_session;
    private unowned Spice.Audio audio;
    private ulong channel_new_id;
    private ulong channel_destroy_id;
    private BoxConfig.SavedProperty[] display_saved_properties;
    private BoxConfig.SavedProperty[] gtk_session_saved_properties;
    private bool closed;

    private PortChannel webdav_channel;

    private GLib.HashTable<Spice.Channel,SpiceChannelHandler> channel_handlers;
    private Display.OpenFDFunc? open_fd;

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
        session = new Session ();
        audio = Spice.Audio.get (session, null);
        gtk_session = GtkSession.get (session);

        Spice.set_session_option (session);
        try {
            var manager = UsbDeviceManager.get (session);

            manager.device_error.connect ( (dev, err) => {
                var device_description = dev.get_description ("%1$s %2$s");
                var box_name = get_box_name ();
                got_error (_("Redirection of USB device “%s” for “%s” failed").printf (device_description, box_name));
                debug ("Error connecting %s to %s: %s", device_description, box_name, err.message);
            });
        } catch (GLib.Error error) {
        }
    }

    private Spice.MainChannel? _main_channel;
    public Spice.MainChannel? main_channel {
            get {
                return _main_channel;
            }

            set {
                _main_channel = value;
                if (_main_channel == null)
                    return;

                main_event_id = main_channel.channel_event.connect (main_event);
                main_mouse_mode_id = main_channel.notify["mouse-mode"].connect(() => {
                    can_grab_mouse = main_channel.mouse_mode != 2;
                });

                can_grab_mouse = main_channel.mouse_mode != 2;
                new_file_transfer_id = main_channel.new_file_transfer.connect (on_new_file_transfer);

                agent_connected_id = main_channel.notify["agent-connected"].connect (() => {
                    is_guest_agent_connected = main_channel.agent_connected;

                    if (is_guest_agent_connected) {
                        var display = get_display (0) as Spice.Display;
                        display.only_downscale = false;
                    }
                });
            }
    }
    ulong main_event_id;
    ulong main_mouse_mode_id;
    ulong new_file_transfer_id;
    ulong agent_connected_id;

    private void main_cleanup () {
        if (main_channel == null)
            return;

        var o = main_channel as Object;
        o.disconnect (main_event_id);
        main_event_id = 0;
        o.disconnect (main_mouse_mode_id);
        main_mouse_mode_id = 0;
        o.disconnect (new_file_transfer_id);
        new_file_transfer_id = 0;
        o.disconnect (agent_connected_id);
        agent_connected_id = 0;
        main_channel = null;
    }

    ~SpiceDisplay () {
        main_cleanup ();
    }

    public SpiceDisplay (Machine machine, BoxConfig config, string host, int port, int tls_port = 0)
        requires (port != 0 || tls_port != 0) {
        this.machine = machine;
        machine.notify["ui-state"].connect (ui_state_changed);

        this.config = config;

        session.host = host;
        if (port != 0)
            session.port = port.to_string ();

        if (tls_port != 0)
            session.tls_port = tls_port.to_string ();

        session.cert_subject = GLib.Environment.get_variable ("BOXES_SPICE_HOST_SUBJECT");

        config.save_properties (gtk_session, gtk_session_saved_properties);
    }

    public SpiceDisplay.with_uri (Machine machine, BoxConfig config, string uri) {
        this.machine = machine;
        machine.notify["ui-state"].connect (ui_state_changed);

        this.config = config;

        session.uri = uri;

        config.save_properties (gtk_session, gtk_session_saved_properties);
    }

    public SpiceDisplay.priv (Machine machine, BoxConfig config) {
        this.machine = machine;
        machine.notify["ui-state"].connect (ui_state_changed);

        this.config = config;

        config.save_properties (gtk_session, gtk_session_saved_properties);
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
            config.save_properties (this, display_saved_properties);
            display.scaling = true;
            display.only_downscale = true;

            displays.replace (n, display);
        }

        return display;
    }

    public override bool should_keep_alive () {
        try {
            var manager = UsbDeviceManager.get (session);
            var devs = get_usb_devices (manager);

            return (!closed && (devs.length > 0));
        } catch (GLib.Error error) {
            return false;
        }
    }

    public override void set_enable_audio (bool enable) {
        session.enable_audio = enable;
    }

    public override Gdk.Pixbuf? get_pixbuf (int n) {
        var display = get_display (n) as Spice.Display;

        if (!display.ready)
            return null;

        /* FIXME: This is a temporary workaround for a mesa issue that causes
         * Boxes to crash when calling spice_display_get_pixbuf ();
         * See https://bugs.freedesktop.org/106811 */
        var libvirt_machine = machine as LibvirtMachine;
        if (libvirt_machine.acceleration_3d) {
            return draw_pixbuf_client_side (display);
        }

        return display.get_pixbuf ();
    }

    private Gdk.Pixbuf draw_pixbuf_client_side (Spice.Display display) {
        Gtk.Allocation alloc;
        var widget = display as Gtk.Widget;
        widget.get_allocation (out alloc);

        var surface = new Cairo.ImageSurface (ARGB32, alloc.width, alloc.height);
        var context = new Cairo.Context (surface);
        widget.draw (context);

        return Gdk.pixbuf_get_from_surface (surface, 0, 0, alloc.width, alloc.height);
    }

    public override void collect_logs (StringBuilder builder) {
        builder.append_printf ("URL: %s\n", uri);
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

    public override void connect_it (owned Display.OpenFDFunc? open_fd = null) {
        // We only initiate connection once
        if (connected)
            return;
        connected = true;
        this.open_fd = (owned) open_fd;

        main_cleanup ();
        channel_handlers = new GLib.HashTable<Spice.Channel,SpiceChannelHandler> (GLib.direct_hash, GLib.direct_equal);

        // FIXME: vala does't want to put this in constructor..
        if (channel_new_id == 0)
            channel_new_id = session.channel_new.connect (on_channel_new);
        if (channel_destroy_id == 0)
            channel_destroy_id = session.channel_destroy.connect (on_channel_destroy);

        session.password = password;
        if (this.open_fd != null)
            session.open_fd (-1);
        else
            session.connect ();
    }

    public override void disconnect_it () {
        var session_object = session as GLib.Object;
        if (channel_new_id > 0) {
            session_object.disconnect (channel_new_id);
            channel_new_id = 0;
        }
        if (channel_destroy_id > 0) {
            session_object.disconnect (channel_destroy_id);
            channel_destroy_id = 0;
        }
        session.disconnect ();
        main_cleanup ();
        channel_handlers = null;
        this.open_fd = null;
        displays.remove_all ();
    }

    private void on_channel_new (Spice.Session session, Spice.Channel channel) {
        var handler = new SpiceChannelHandler (this, channel, open_fd);
        channel_handlers.set (channel, handler);

        if (channel is Spice.DisplayChannel) {
            if (channel.channel_id != 0)
                return;

            access_start ();
        }

        if (channel is Spice.WebdavChannel) {
            webdav_channel = channel as Spice.PortChannel;

            App.app.shared_folders_manager.get_folders (machine.config.uuid);
            session.shared_dir = get_user_pkgconfig (machine.config.uuid);

        }
    }

    private void on_channel_destroy (Spice.Session session, Spice.Channel channel) {
        if (!(channel is Spice.DisplayChannel))
            return;

        var display = channel as DisplayChannel;
        hide (display.channel_id);
        access_finish ();
    }

    private void main_event (ChannelEvent event) {
        switch (event) {
        case ChannelEvent.CLOSED:
            closed = true;
            disconnected (false);
            break;

        case ChannelEvent.ERROR_AUTH:
            break;

        case ChannelEvent.ERROR_CONNECT:
        case ChannelEvent.ERROR_TLS:
        case ChannelEvent.ERROR_LINK:
        case ChannelEvent.ERROR_IO:
            debug ("main SPICE channel error: %d", event);
            closed = true;
            disconnected (true);
            break;

        case ChannelEvent.OPENED:
            break;

        default:
            debug ("unhandled main SPICE channel event: %d", event);
            break;
        }
    }

    public override void transfer_files (GLib.List<string> uris) {
        GLib.File[] files = {};
        foreach (string uri in uris) {
            var file = GLib.File.new_for_uri (uri);
            files += file;
        }
        files += null;

        main_channel.file_copy_async.begin (files, FileCopyFlags.NONE, null, null);
    }

    private void on_new_file_transfer (Spice.MainChannel main_channel, Object transfer_task) {
        DisplayPage page = machine.window.display_page;
        page.add_transfer (transfer_task);
    }

    public override void send_keys (uint[] keyvals) {
        // TODO: multi display
        var display = get_display (0) as Spice.Display;

        display.send_keys (keyvals, DisplayKeyEvent.CLICK);
    }

    private GLib.GenericArray<Spice.UsbDevice> get_usb_devices (UsbDeviceManager manager) {
        GLib.GenericArray<Spice.UsbDevice> ret = new GLib.GenericArray<Spice.UsbDevice> ();
        var devs = manager.get_devices ();

        if (Environment.get_variable ("BOXES_USB_REDIR_ALL") != null)
            return devs;

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

    public GLib.ListStore get_usb_devices_model () {
        GLib.ListStore model = new GLib.ListStore (typeof (Boxes.UsbDevice));

        GLib.GenericArray<Spice.UsbDevice> devs = new GLib.GenericArray<Spice.UsbDevice> ();
        UsbDeviceManager manager;
        try {
            manager = UsbDeviceManager.get (session);
            devs = get_usb_devices (manager);
        }  catch (GLib.Error error) {
            warning ("Failed to obtain usb devices list: %s", error.message);

            return model;
        }

        for (int i = 0; i < devs.length; i++) {
            var dev = devs[i];

            var usb_device = new Boxes.UsbDevice () {
                title = dev.get_description ("%1$s %2$s"),
                active = manager.is_device_connected (dev),
            };

            usb_device.notify["active"].connect (() => {
                if (!usb_device.active) {
                    manager.disconnect_device (dev);

                    return;
                }

                manager.connect_device_async.begin (dev, null, (obj, res) => {
                    try {
                        manager.connect_device_async.end (res);
                    } catch (GLib.Error err) {
                        usb_device.active = false;
                        var device_desc = dev.get_description ("%1$s %2$s");
                        var box_name = get_box_name ();
                        var msg = _("Redirection of USB device “%s” for “%s” failed");

                        got_error (msg.printf (device_desc, box_name));
                        debug ("Error connecting %s to %s: %s",
                               device_desc,
                               box_name, err.message);
                    }
                });
            });

            model.append (usb_device);
        }

        return model;
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

private class Boxes.SpiceChannelHandler : GLib.Object {
    private unowned SpiceDisplay display;
    private Spice.Channel channel;
    private unowned Display.OpenFDFunc? open_fd;

    public SpiceChannelHandler (SpiceDisplay display, Spice.Channel channel, Display.OpenFDFunc? open_fd = null) {
        this.display = display;
        this.channel = channel;
        this.open_fd = open_fd;
        var id = channel.channel_id;

        if (open_fd != null)
            channel.open_fd.connect (on_open_fd);

        if (channel is Spice.MainChannel)
            display.main_channel = (channel as Spice.MainChannel);

        if (channel is Spice.DisplayChannel) {
            if (id != 0)
                return;

            var spice_display = display.get_display (id) as Spice.Display;
            spice_display.notify["ready"].connect (on_display_ready);
        }

        if (channel is Spice.WebdavChannel) {
            if (open_fd != null)
                on_open_fd (channel, 0);
            else
                channel.connect ();
        }
    }

    private void on_display_ready (GLib.Object object, GLib.ParamSpec param_spec) {
        var spice_display = object as Spice.Display;
        if (spice_display.ready)
            display.show (spice_display.channel_id);
        else
            display.hide (spice_display.channel_id);
    }

    private void on_open_fd (Spice.Channel channel, int with_tls) {
        int fd;

        fd = open_fd ();
        channel.open_fd (fd);
    }
}
