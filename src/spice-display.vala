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
    private string shared_folder;
    private GLib.Settings shared_folder_settings;

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
        gtk_session_saved_properties = {
            BoxConfig.SavedProperty () { name = "auto-clipboard", default_value = true },
        };

        need_password = false;
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
            }
    }
    ulong main_event_id;
    ulong main_mouse_mode_id;
    ulong new_file_transfer_id;

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

        config.save_properties (gtk_session, gtk_session_saved_properties);

        init_shared_folders ();
    }

    public SpiceDisplay.with_uri (Machine machine, BoxConfig config, string uri) {
        this.machine = machine;
        machine.notify["ui-state"].connect (ui_state_changed);

        this.config = config;

        session.uri = uri;

        config.save_properties (gtk_session, gtk_session_saved_properties);

        init_shared_folders ();
    }

    public SpiceDisplay.priv (Machine machine, BoxConfig config) {
        this.machine = machine;
        machine.notify["ui-state"].connect (ui_state_changed);

        this.config = config;

        config.save_properties (gtk_session, gtk_session_saved_properties);

        init_shared_folders ();
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

        return display.get_pixbuf ();
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

        if (channel is Spice.WebdavChannel)
            webdav_channel = channel as Spice.PortChannel;
    }

    private void on_channel_destroy (Spice.Session session, Spice.Channel channel) {
        if (!(channel is Spice.DisplayChannel))
            return;

        var display = channel as DisplayChannel;
        hide (display.channel_id);
        access_finish ();
    }

    private bool add_shared_folder (string path, string name) {
        if (!FileUtils.test (shared_folder, FileTest.IS_DIR))
            Posix.unlink (shared_folder);

        if (!FileUtils.test (shared_folder, FileTest.EXISTS)) {
            var ret = Posix.mkdir (shared_folder, 0755);

            if (ret == -1) {
                warning (strerror (errno));

                return false;
            }
        }

        var link_path = GLib.Path.build_filename (shared_folder, name);

        var ret = GLib.FileUtils.symlink (path, link_path);
        if (ret == -1) {
            warning (strerror (errno));

            return false;
        }
        add_gsetting_shared_folder (path, name);

        return true;
    }

    private void remove_shared_folder (string name) {
        if (!FileUtils.test (shared_folder, FileTest.EXISTS) || !FileUtils.test (shared_folder, FileTest.IS_DIR))
            return;

        var to_remove = GLib.Path.build_filename (shared_folder, name);
        Posix.unlink (to_remove);

        remove_gsetting_shared_folder (name);
    }

    private HashTable<string, string>? get_shared_folders () {
        if (!FileUtils.test (shared_folder, FileTest.EXISTS) || !FileUtils.test (shared_folder, FileTest.IS_DIR))
            return null;

        var hash = new HashTable <string, string> (str_hash, str_equal);
        try {
            Dir dir = Dir.open (shared_folder, 0);
            string? name = null;

            while ((name = dir.read_name ()) != null) {
                var path = Path.build_filename (shared_folder, name);
                if (FileUtils.test (path, FileTest.IS_SYMLINK)) {
                    var folder = GLib.FileUtils.read_link (path);

                    hash[name] = folder;
                }
            }
        } catch (GLib.FileError err) {
            warning (err.message);
        }

        return hash;
    }

    private void init_shared_folders () {
        shared_folder = GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "gnome-boxes", machine.config.uuid);

        shared_folder_settings = new GLib.Settings ("org.gnome.boxes");
        var hash = parse_shared_folders ();
        var names = hash.get_keys ();
        foreach (var name in names) {
            add_shared_folder (hash[name], name);
        }
    }

    private HashTable<string, string> parse_shared_folders () {
        var hash = new HashTable <string, string> (str_hash, str_equal);

        string shared_folders = shared_folder_settings.get_string("shared-folders");
        if (shared_folders == "")
            return hash;

        try {
            GLib.Variant? entry = null;
            string uuid_str;
            string path_str;
            string name_str;

            var variant = Variant.parse (new GLib.VariantType.array (GLib.VariantType.VARIANT), shared_folders);
            VariantIter iter = variant.iterator ();
            while (iter.next ("v",  &entry)) {
                entry.lookup ("uuid", "s", out uuid_str);
                entry.lookup ("path", "s", out path_str);
                entry.lookup ("name", "s", out name_str);

                if (machine.config.uuid == uuid_str)
                    hash[name_str] = path_str;
            }
        } catch (VariantParseError err) {
            warning (err.message);
        }

        return hash;
    }

    private void add_gsetting_shared_folder (string path, string name) {
        var variant_builder = new GLib.VariantBuilder (new GLib.VariantType.array (VariantType.VARIANT));

        string shared_folders = shared_folder_settings.get_string ("shared-folders");
        if (shared_folders != "") {
            try {
                GLib.Variant? entry = null;

                var variant = Variant.parse (new GLib.VariantType.array (GLib.VariantType.VARIANT), shared_folders);
                VariantIter iter = variant.iterator ();
                while (iter.next ("v",  &entry)) {
                    variant_builder.add ("v",  entry);
                }
            } catch (VariantParseError err) {
                warning (err.message);
            }
        }

        var entry_variant_builder = new GLib.VariantBuilder (GLib.VariantType.VARDICT);

        var uuid_variant = new GLib.Variant ("s", machine.config.uuid);
        var path_variant = new GLib.Variant ("s", path);
        var name_variant = new GLib.Variant ("s", name);
        entry_variant_builder.add ("{sv}", "uuid", uuid_variant);
        entry_variant_builder.add ("{sv}", "path", path_variant);
        entry_variant_builder.add ("{sv}", "name", name_variant);
        var entry_variant = entry_variant_builder.end ();

        variant_builder.add ("v",  entry_variant);
        var variant = variant_builder.end ();

        shared_folder_settings.set_string ("shared-folders", variant.print (true));
    }

    private void remove_gsetting_shared_folder (string name) {
        var variant_builder = new GLib.VariantBuilder (new GLib.VariantType.array (VariantType.VARIANT));

        string shared_folders = shared_folder_settings.get_string ("shared-folders");
        if (shared_folders == "")
            return;

        try {
            GLib.Variant? entry = null;
            string name_str;
            string uuid_str;

            var variant = Variant.parse (new GLib.VariantType.array (GLib.VariantType.VARIANT), shared_folders);
            VariantIter iter = variant.iterator ();
            while (iter.next ("v",  &entry)) {
                entry.lookup ("uuid", "s", out uuid_str);
                entry.lookup ("name", "s", out name_str);

                if (uuid_str == machine.config.uuid && name_str == name)
                    continue;

                variant_builder.add ("v", entry);
            }
            variant = variant_builder.end ();

            shared_folder_settings.set_string ("shared-folders", variant.print (true));
        } catch (VariantParseError err) {
            warning (err.message);
        }
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

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Boxes.Property> ();

        switch (page) {
        case PropertiesPage.GENERAL:
            var toggle = new Gtk.Switch ();
            gtk_session.bind_property ("auto-clipboard", toggle, "active",
                                       BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
            toggle.halign = Gtk.Align.START;
            add_property (ref list, _("Share Clipboard"), toggle);

            if (!connected || main_channel.agent_connected)
                break;

            var message = _("SPICE guest tools are not installed. These tools improve user experience and enable host and box interactions, such as copy&amp;paste. Please visit <a href=\"http://www.spice-space.org/download.html\">http://www.spice-space.org/download.html</a> to download and install these tools from within the box.");
            var label = new Gtk.Label (message);
            label.vexpand = true;
            label.valign = Gtk.Align.END;
            label.wrap = true;
            label.max_width_chars = 80;
            label.use_markup = true;
            label.get_style_context ().add_class ("boxes-spice-tools-notice-label");

            add_property (ref list, null, label);
            break;

        case PropertiesPage.DEVICES:
            try {
                var manager = UsbDeviceManager.get (session);
                var devs = get_usb_devices (manager);

                if (connected && devs.length > 0) {
                    devs.sort ( (a, b) => {
                        string str_a = a.get_description ("    %1$s %2$s");
                        string str_b = b.get_description ("    %1$s %2$s");

                        return strcmp (str_a, str_b);
                    });

                    var frame = create_usb_frame (manager, devs);

                    var usb_property = add_property (ref list, _("USB devices"), new Gtk.Label (""), frame);

                    manager.device_added.connect ((manager, dev) => {
                        usb_property.refresh_properties ();
                    });
                    manager.device_removed.connect ((manager, dev) => {
                        usb_property.refresh_properties ();
                    });
                }
            } catch (GLib.Error error) {
            }

            if (webdav_channel == null || !webdav_channel.port_opened)
                break;

            session.shared_dir = shared_folder;

            var frame = create_shared_folders_frame ();
            add_property (ref list, _("Folder Shares"), new Gtk.Label (""), frame);

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

    private Gtk.Frame create_usb_frame (UsbDeviceManager manager, GLib.GenericArray<UsbDevice> devs) {
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
                              var msg = _("Redirection of USB device “%s” for “%s” failed");
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

        return frame;
    }

    private Gtk.Frame create_shared_folders_frame () {
        var frame = new Gtk.Frame (null);
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        var listbox = new Gtk.ListBox ();
        var button_plus = new Gtk.Button.from_icon_name ("list-add-symbolic", IconSize.BUTTON);
        button_plus.halign = Gtk.Align.CENTER;
        button_plus.get_style_context ().add_class ("flat");

        box.pack_start (listbox, true, true, 0);
        box.pack_end (button_plus, false, false, 6);
        frame.add (box);

        var popover = new SharedFolderPopover ();

        button_plus.clicked.connect (() => {
            popover.relative_to = button_plus;
            popover.target_position = -1;

            popover.popup ();
        });

        listbox.row_activated.connect ((row) => {
            popover.relative_to = row;
            popover.target_position = row.get_index ();

            var folder_row = row as SharedFolderRow;
            popover.file_chooser_button.set_uri ("file://" + folder_row.folder_path);
            popover.name_entry.set_text (folder_row.folder_name);

            popover.popup ();
        });

        var hash = get_shared_folders ();
        if (hash != null) {
            var keys = hash.get_keys ();
            foreach (var key in keys) {
                add_listbox_row (listbox, hash[key], key, -1);
            }
        }

        popover.saved.connect ((path, name, target_position) => {
            // Update previous entry
            if (target_position != - 1) {
                var row = listbox.get_row_at_index (target_position) as Boxes.SharedFolderRow;
                remove_shared_folder (row.folder_name);
            }

            if (add_shared_folder (path, name))
                add_listbox_row (listbox, path, name, target_position);
        });

        return frame;
    }

    private void add_listbox_row (Gtk.ListBox listbox, string path, string name, int target_position) {
        var listboxrow = new SharedFolderRow (path, name);

        if (target_position != -1)
            listbox.remove (listbox.get_row_at_index (target_position));

        listbox.insert (listboxrow, target_position);

        listboxrow.removed.connect (() => {
            listbox.remove (listboxrow);
            remove_shared_folder (name);
        });
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

// FIXME: this kind of function should be part of spice-gtk
static void spice_validate_uri (string uri_as_text,
                                out int? port = null,
                                out int? tls_port = null) throws Boxes.Error {
    var uri = Xml.URI.parse (uri_as_text);

    if (uri == null)
        throw new Boxes.Error.INVALID (_("Invalid URL"));

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

    switch (uri.scheme) {
    case "spice":
        if (port <= 0 && tls_port <= 0)
            throw new Boxes.Error.INVALID (_("Missing port in Spice URL"));
        break;
    case "spice+unix":
        if (port > 0 || uri.query_raw != null || uri.query != null)
            throw new Boxes.Error.INVALID (_("Invalid URL"));
        break;
    default:
        throw new Boxes.Error.INVALID (_("Invalid URL"));
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/properties-shared-folder-row.ui")]
private class Boxes.SharedFolderRow : Gtk.ListBoxRow {
    public string folder_path { set; get; }
    public string folder_name { set; get; }

    public signal void removed ();
    [GtkChild]
    private Gtk.Label folder_path_label;
    [GtkChild]
    private Gtk.Label folder_name_label;

    public SharedFolderRow (string path, string name) {
        this.folder_path = path;
        this.folder_name = name;

        bind_property ("folder_path", folder_path_label, "label", BindingFlags.SYNC_CREATE);
        bind_property ("folder_name", folder_name_label, "label", BindingFlags.SYNC_CREATE);
    }

    [GtkCallback]
    private void on_delete_button_clicked () {
        removed ();
    }
}
