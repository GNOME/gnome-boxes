// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;
using Gtk;

private class Boxes.LibvirtMachine: Boxes.Machine {
    public GVir.Domain domain;
    public GVirConfig.Domain domain_config;
    public GVir.Connection connection;
    private string? storage_volume_path;
    public VMCreator? vm_creator; // Under installation if this is set to non-null

    public bool save_on_quit {
        get { return source.get_boolean ("source", "save-on-quit"); }
        set { source.set_boolean ("source", "save-on-quit", value); }
    }

    private ulong started_id;
    public override void connect_display () {
        if (display != null)
            return;

        if (state != MachineState.RUNNING) {
            if (started_id != 0)
                return;

            if (state == MachineState.PAUSED) {
                started_id = domain.resumed.connect (() => {
                    domain.disconnect (started_id);
                    started_id = 0;
                    connect_display ();
                });
                try {
                    domain.resume ();
                } catch (GLib.Error error) {
                    warning (error.message);
                }
            } else {
                started_id = domain.started.connect (() => {
                    domain.disconnect (started_id);
                    started_id = 0;
                    connect_display ();
                });
                try {
                    domain.start (0);
                } catch (GLib.Error error) {
                    warning (error.message);
                }
            }
        }

        update_display ();
        display.connect_it ();
    }

    struct MachineStat {
        int64 timestamp;
        double cpu_time;
        double cpu_time_abs;
        double cpu_guest_percent;
        double memory_percent;
        DomainDiskStats disk;
        double disk_read;
        double disk_write;
        DomainInterfaceStats net;
        double net_read;
        double net_write;
    }

    private uint ram_update_timeout = 0;
    private uint storage_update_timeout = 0;
    private uint stats_update_timeout;
    private Cancellable stats_cancellable;

    static const int STATS_SIZE = 20;
    private MachineStat[] stats;
    construct {
        stats = new MachineStat[STATS_SIZE];
        stats_cancellable = new Cancellable ();
    }

    public void update_domain_config () {
        try {
            domain_config = domain.get_config (GVir.DomainXMLFlags.NONE);

            var volume = get_storage_volume (connection, domain, null);
            storage_volume_path = (volume != null)? volume.get_path () : null;
        } catch (GLib.Error error) {
            critical ("Failed to fetch configuration for domain '%s': %s", domain.get_name (), error.message);
        }
    }

    public LibvirtMachine (CollectionSource source,
                           GVir.Connection connection,
                           GVir.Domain     domain) throws GLib.Error {
        var config = domain.get_config (GVir.DomainXMLFlags.INACTIVE);
        var item_name = config.get_title () ?? domain.get_name ();
        base (source, item_name);

        debug ("new libvirt machine: " + domain.get_name ());
        this.config = new DisplayConfig (source, domain.get_uuid ());
        this.connection = connection;
        this.domain = domain;

        try {
            var s = domain.get_info ().state;
            switch (s) {
            case DomainState.RUNNING:
            case DomainState.BLOCKED:
                state = MachineState.RUNNING;
                break;
            case DomainState.PAUSED:
                state = MachineState.PAUSED;
                break;
            case DomainState.SHUTDOWN:
            case DomainState.SHUTOFF:
            case DomainState.CRASHED:
                state = MachineState.STOPPED;
                break;
            default:
            case DomainState.NONE:
                state = MachineState.UNKNOWN;
                break;
            }
        } catch (GLib.Error error) {
            state = MachineState.UNKNOWN;
        }

        domain.started.connect (() => { state = MachineState.RUNNING; });
        domain.suspended.connect (() => { state = MachineState.PAUSED; });
        domain.resumed.connect (() => { state = MachineState.RUNNING; });
        domain.stopped.connect (() => { state = MachineState.STOPPED; });

        update_domain_config ();
        domain.updated.connect (update_domain_config);

        load_screenshot ();
        set_screenshot_enable (true);
        set_stats_enable (true);
    }

    private void update_cpu_stat (DomainInfo info, ref MachineStat stat) {
        var prev = stats[STATS_SIZE - 1];

        if (info.state == DomainState.CRASHED ||
            info.state == DomainState.SHUTOFF)
            return;

        stat.cpu_time = info.cpuTime - prev.cpu_time_abs;
        stat.cpu_time_abs = info.cpuTime;
        // hmm, where does this x10 come from?
        var dt = (stat.timestamp - prev.timestamp) * 10;
        var percent = stat.cpu_time / dt;
        percent = percent / info.nrVirtCpu;
        stat.cpu_guest_percent = percent.clamp (0, 100);
    }

    private void update_mem_stat (DomainInfo info, ref MachineStat stat) {
        if (info.state != DomainState.RUNNING)
            return;

        stat.memory_percent = info.memory * 100.0 / info.maxMem;
    }

    private async void update_io_stat (DomainInfo info, MachineStat *stat) {
        if (info.state != DomainState.RUNNING)
            return;

        try {
            var disk = get_domain_disk ();
            if (disk == null)
                return;

            yield run_in_thread ( () => {
                    stat.disk = disk.get_stats ();
                } );
            var prev = stats[STATS_SIZE - 1];
            if (prev.disk != null) {
                stat.disk_read = (stat.disk.rd_bytes - prev.disk.rd_bytes);
                stat.disk_write = (stat.disk.wr_bytes - prev.disk.wr_bytes);
            }
        } catch (GLib.Error err) {
            warning ("Failed to fetch I/O statistics for %s: %s", name, err.message);
        }
    }

    private async void update_net_stat (DomainInfo info, MachineStat *stat) {
        if (info.state != DomainState.RUNNING)
            return;

        try {
            var net = get_domain_network_interface ();
            if (net == null)
                return;

            yield run_in_thread ( () => {
                    stat.net = net.get_stats ();
                } );
            var prev = stats[STATS_SIZE - 1];
            if (prev.net != null) {
                stat.net_read = (stat.net.rx_bytes - prev.net.rx_bytes);
                stat.net_write = (stat.net.tx_bytes - prev.net.tx_bytes);
            }
        } catch (GLib.Error err) {
            warning ("Failed to fetch network statistics for %s: %s", name, err.message);
        }
    }

    public signal void stats_updated ();

    public double[] cpu_stats;
    public double[] io_stats;
    public double[] net_stats;
    private async void update_stats () {
        try {
            var now = get_monotonic_time ();
            var stat = MachineStat () { timestamp = now };
            var info = yield domain.get_info_async (stats_cancellable);

            update_cpu_stat (info, ref stat);
            update_mem_stat (info, ref stat);
            yield update_io_stat (info, &stat);
            yield update_net_stat (info, &stat);

            stats = stats[1:STATS_SIZE];
            stats += stat;

        } catch (IOError.CANCELLED err) {
            return;
        } catch (GLib.Error err) {
            warning (err.message);
        }

        cpu_stats = {};
        io_stats = {};
        net_stats = {};

        foreach (var stat in stats) {
            cpu_stats += stat.cpu_guest_percent;
            net_stats += (stat.net_read + stat.net_write);
            io_stats += (stat.disk_read + stat.disk_write);
        }

        stats_updated ();
    }

    private void set_stats_enable (bool enable) {
        if (enable) {
            debug ("enable statistics for " + name);
            if (stats_update_timeout != 0)
                return;

            stats_cancellable.reset ();
            var stats_updating = false;
            stats_update_timeout = Timeout.add_seconds (1, () => {
                if (stats_updating) {
                    warning ("Fetching of stats for '%s' is taking too long. Probably a libvirt bug.", name);

                    return true;
                }

                stats_updating = true;
                update_stats.begin (() => { stats_updating = false; });

                return true;
            });
        } else {
            debug ("disable statistics for " + name);
            if (stats_update_timeout != 0) {
                stats_cancellable.cancel ();
                GLib.Source.remove (stats_update_timeout);
            }
            stats_update_timeout = 0;
        }
    }

    public void try_change_name (string name) throws Boxes.Error {
        try {
            var config = domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            // Te use libvirt "title" for free form user name
            config.title = name;
            // This will take effect only after next reboot, but we use pending/inactive config for name and title
            domain.set_config (config);

            this.name = name;
        } catch (GLib.Error error) {
            warning ("Failed to change title of box '%s' to '%s': %s",
                     domain.get_name (), name, error.message);
            throw new Boxes.Error.INVALID ("Invalid libvirt title");
        }
    }

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Boxes.Property> ();

        switch (page) {
        case PropertiesPage.LOGIN:
            add_string_property (ref list, _("Name"), name, (property, name) => {
                try_change_name (name);
            });
            add_string_property (ref list, _("Virtualizer"), source.uri);
            add_string_property (ref list, _("URI"), display.uri);
            break;

        case PropertiesPage.SYSTEM:
            add_ram_property (ref list);
            add_storage_property (ref list);
            break;

        case PropertiesPage.DISPLAY:
            add_string_property (ref list, _("Protocol"), display.protocol);
            break;
        }

        list.concat (display.get_properties (page));

        return list;
    }

    private void update_display () {
        string type, port, socket, host;

        update_domain_config ();

        try {
            var xmldoc = domain_config.to_xml ();
            type = extract_xpath (xmldoc, "string(/domain/devices/graphics/@type)", true);
            port = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@port)");
            socket = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@socket)");
            host = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@listen)");
        } catch (GLib.Error error) {
            warning (error.message);
            return;
        }

        if (host == null || host == "")
            host = "localhost";

        switch (type) {
        case "spice":
            display = new SpiceDisplay (config, host, int.parse (port));
            break;

        case "vnc":
            display = new VncDisplay (config, host, int.parse (port));
            break;

        default:
            warning ("unsupported display of type " + type);
            break;
        }
    }

    public override string get_screenshot_prefix () {
        return domain.get_uuid ();
    }

    public override async Gdk.Pixbuf? take_screenshot () throws GLib.Error {
        var state = DomainState.NONE;
        try {
            state = (yield domain.get_info_async (null)).state;
        } catch (GLib.Error error) {
            warning ("Failed to get information on '%s'", name);
        }

        if (state != DomainState.RUNNING && state != DomainState.PAUSED)
            return null;

        var stream = connection.get_stream (0);
        yield run_in_thread (()=> {
            domain.screenshot (stream, 0, 0);
        });

        var loader = new Gdk.PixbufLoader ();
        var input_stream = stream.get_input_stream ();
        var buffer = new uint8[65535];
        ssize_t length = 0;
        do {
            length = yield input_stream.read_async (buffer);
            loader.write (buffer[0:length]);
        } while (length > 0);
        loader.close ();

        return loader.get_pixbuf ();
    }

    public override void delete (bool by_user = true) {
        debug ("delete libvirt machine: " + name);
        base.delete (by_user);

        set_stats_enable (false);

        if (by_user) {
            force_shutdown (false);

            try {
                if (connection == App.app.default_connection) {
                    var volume = get_storage_volume (connection, domain, null);
                    if (volume != null)
                        volume.delete (0);
                }
                domain.delete (DomainDeleteFlags.SAVED_STATE);
            } catch (GLib.Error err) {
                warning (err.message);
            }
        }
    }

    public async void suspend () throws GLib.Error {
        (save_on_quit) ? yield domain.save_async (0, null) : domain.suspend ();
    }

    public void force_shutdown (bool confirm = true) {
        if (confirm) {
            var dialog = new Gtk.MessageDialog (App.app.window,
                                                Gtk.DialogFlags.DESTROY_WITH_PARENT,
                                                Gtk.MessageType.QUESTION,
                                                Gtk.ButtonsType.OK_CANCEL,
                                                _("When you force shutdown, the box may lose data."));
            var response = dialog.run ();
            dialog.destroy ();

            if (response != Gtk.ResponseType.OK)
                return;
        }

        debug ("Force shutdown '%s'..", name);
        try {
            domain.stop (0);
        } catch (GLib.Error error) {
            warning ("Failed to shutdown '%s': %s", domain.get_name (), error.message);
        }
    }

    private GVir.DomainDisk? get_domain_disk () throws GLib.Error {
        var disk = null as GVir.DomainDisk;

        foreach (var device_config in domain_config.get_devices ()) {
            if (device_config is GVirConfig.DomainDisk) {
                var disk_config = device_config as GVirConfig.DomainDisk;
                var disk_type = disk_config.get_guest_device_type ();

                // Prefer Boxes' managed volume over other disks
                if (disk_type == GVirConfig.DomainDiskGuestDeviceType.DISK &&
                    disk_config.get_source () == storage_volume_path) {
                    disk = Object.new (typeof (GVir.DomainDisk), "domain", domain, "config", device_config) as GVir.DomainDisk;

                    break;
                }
            }
        }

        return disk;
    }

    private GVir.DomainInterface? get_domain_network_interface () throws GLib.Error {
        var net = null as GVir.DomainInterface;

        // FiXME: We currently only entertain one network interface
        foreach (var device_config in domain_config.get_devices ()) {
            if (device_config is GVirConfig.DomainInterface) {
                net = Object.new (typeof (GVir.DomainInterface), "domain", domain, "config", device_config) as GVir.DomainInterface;
                break;
            }
        }

        return net;
    }

    private void update_ram_property (Boxes.Property property) {
        try {
            var config = domain.get_config (GVir.DomainXMLFlags.INACTIVE);

            // we uses KiB unit, convert to MiB
            var actual = domain_config.memory / 1024;
            var pending = config.memory / 1024;

            debug ("RAM actual: %llu, pending: %llu", actual, pending);
            // somehow, there are rounded errors, so let's forget about 1Mb diff
            property.changes_pending = (actual - pending) > 1; // no need for abs()

        } catch (GLib.Error e) {}
    }

    private void add_ram_property (ref List list) {
        try {
            var max_ram = connection.get_node_info ().memory;

            var property = add_size_property (ref list,
                                              _("RAM"),
                                              domain_config.memory,
                                              Osinfo.MEBIBYTES / Osinfo.KIBIBYTES,
                                              max_ram,
                                              Osinfo.MEBIBYTES / Osinfo.KIBIBYTES,
                                              on_ram_changed);

            this.notify["state"].connect (() => {
                if (state == MachineState.STOPPED)
                    property.changes_pending = false;
            });

            update_ram_property (property);
        } catch (GLib.Error error) {}
    }

    private void on_ram_changed (Boxes.Property property, uint64 value) {
        // Ensure that we don't end-up changing RAM like a 1000 times a second while user moves the slider..
        if (ram_update_timeout != 0)
            Source.remove (ram_update_timeout);

        ram_update_timeout = Timeout.add_seconds (1, () => {
            try {
                var config = domain.get_config (GVir.DomainXMLFlags.INACTIVE);
                config.memory = value;
                domain.set_config (config);
                debug ("RAM changed to %llu", value);
                notify_reboot_required ();
            } catch (GLib.Error error) {
                warning ("Failed to change RAM of box '%s' to %llu: %s",
                         domain.get_name (),
                         value,
                         error.message);
            }
            ram_update_timeout = 0;
            update_ram_property (property);

            return false;
        });
    }

    private void notify_reboot_required () {
        Notificationbar.OKFunc reboot = () => {
            debug ("Rebooting '%s'..", name);
            try {
                domain.reboot (0);
            } catch (GLib.Error error) {
                warning ("Failed to reboot '%s': %s", domain.get_name (), error.message);
            }
        };
        var message = _("Changes require restart of '%s'. Attempt restart?").printf (name);
        App.app.notificationbar.display_for_action (message, Gtk.Stock.YES, (owned) reboot);
    }

    private void add_storage_property (ref List list) {
        StoragePool pool;

        var volume = get_storage_volume (connection, domain, out pool);
        if (volume == null)
            return;

        try {
            var volume_info = volume.get_info ();
            var pool_info = pool.get_info ();
            var max_storage = (volume_info.capacity + pool_info.available)  / Osinfo.KIBIBYTES;

            add_size_property (ref list,
                               _("Storage"),
                               volume_info.capacity / Osinfo.KIBIBYTES,
                               volume_info.capacity / Osinfo.KIBIBYTES,
                               max_storage,
                               Osinfo.GIBIBYTES / Osinfo.KIBIBYTES,
                               on_storage_changed);
        } catch (GLib.Error error) {
            warning ("Failed to get information on volume '%s' or it's parent pool: %s",
                     volume.get_name (),
                     error.message);
        }
    }

    private void on_storage_changed (Boxes.Property property, uint64 value) {
        // Ensure that we don't end-up changing storage like a 1000 times a second while user moves the slider..
        if (storage_update_timeout != 0)
            Source.remove (storage_update_timeout);

        storage_update_timeout = Timeout.add_seconds (1, () => {
            var volume = get_storage_volume (connection, domain, null);
            if (volume == null)
                return false;

            try {
                if (is_running ()) {
                    var disk = get_domain_disk ();
                    if (disk != null)
                        disk.resize (value, 0);
                } else
                    // Currently this never happens as properties page cant be reached without starting the machine
                    volume.resize (value * Osinfo.KIBIBYTES, StorageVolResizeFlags.NONE);
                debug ("Storage changed to %llu", value);
            } catch (GLib.Error error) {
                warning ("Failed to change storage capacity of volume '%s' to %llu: %s",
                         volume.get_name (),
                         value,
                         error.message);
            }
            storage_update_timeout = 0;

            return false;
        });
    }
}
