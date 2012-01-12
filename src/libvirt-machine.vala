// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;
using Gtk;

private class Boxes.LibvirtMachine: Boxes.Machine {
    public GVir.Domain domain;
    public GVir.Connection connection;
    public DomainState state {
        get {
            try {
                return domain.get_info ().state;
            } catch (GLib.Error error) {
                return DomainState.NONE;
            }
        }
    }

    public bool save_on_quit {
        get { return source.get_boolean ("source", "save-on-quit"); }
        set { source.set_boolean ("source", "save-on-quit", value); }
    }

    public override void disconnect_display () {
        if (_connect_display == false)
            return;

        _connect_display = false;
        app.display_page.remove_display ();
        display = null;
    }

    private ulong started_id;
    public override void connect_display () {
        if (_connect_display) {
            update_display ();
            return;
        }

        if (state != DomainState.RUNNING) {
            if (started_id != 0)
                return;

            if (state == DomainState.PAUSED) {
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

        _connect_display = true;
        update_display ();
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

    static const int STATS_SIZE = 20;
    private MachineStat[] stats;
    construct {
        stats = new MachineStat[STATS_SIZE];
    }

    public LibvirtMachine (CollectionSource source, Boxes.App app,
                           GVir.Connection connection, GVir.Domain domain) {
        base (source, app, domain.get_name ());

        this.config = new DisplayConfig (source, domain.get_uuid ());
        this.connection = connection;
        this.domain = domain;

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
        if (!is_running ())
            return;

        stat.memory_percent = info.memory * 100.0 / info.maxMem;
    }

    private void update_io_stat (ref MachineStat stat) {
        if (!is_running ())
            return;

        try {
            // FIXME: switch to domain.get_devices () and loop over all interfaces
            var xmldoc = domain.get_config (0).to_xml ();
            var target_dev = extract_xpath (xmldoc,
                "string(/domain/devices/disk[@type='file']/target/@dev)", true);
            if (target_dev == "")
                return;

            var disk = GLib.Object.new (typeof (GVir.DomainDisk),
                                        "path", target_dev,
                                        "domain", domain) as GVir.DomainDisk;
            stat.disk = disk.get_stats ();
            var prev = stats[STATS_SIZE - 1];
            if (prev.disk != null) {
                stat.disk_read = (stat.disk.rd_bytes - prev.disk.rd_bytes);
                stat.disk_write = (stat.disk.wr_bytes - prev.disk.wr_bytes);
            }
        } catch (GLib.Error err) {
        }
    }


    private void update_net_stat (ref MachineStat stat) {
        if (!is_running ())
            return;

        try {
            // FIXME: switch to domain.get_devices () and loop over all interfaces
            var xmldoc = domain.get_config (0).to_xml ();
            var target_dev = extract_xpath (xmldoc,
                "string(/domain/devices/interface[@type='network']/target/@dev)", true);
            if (target_dev == "")
                return;

            var net = GLib.Object.new (typeof (GVir.DomainInterface),
                                       "path", target_dev,
                                       "domain", domain) as GVir.DomainInterface;
            stat.net = net.get_stats ();
            var prev = stats[STATS_SIZE - 1];
            if (prev.net != null) {
                stat.net_read = (stat.net.rx_bytes - prev.net.rx_bytes);
                stat.net_write = (stat.net.tx_bytes - prev.net.tx_bytes);
            }
        } catch (GLib.Error err) {
        }
    }

    public signal void stats_updated ();

    public double[] cpu_stats;
    public double[] io_stats;
    public double[] net_stats;
    private void update_stats () {
        try {
            var now = get_monotonic_time ();
            var stat = MachineStat () { timestamp = now };
            var info = domain.get_info ();

            update_cpu_stat (info, ref stat);
            update_mem_stat (info, ref stat);
            update_io_stat (ref stat);
            update_net_stat (ref stat);

            stats = stats[1:STATS_SIZE];
            stats += stat;

        } catch (GLib.Error err) {
            warning (err.message);
        }

        cpu_stats = {};
        io_stats = {};
        net_stats = {};

        foreach (var s in stats) {
            cpu_stats += s.cpu_guest_percent;
        }
        foreach (var s in stats) {
            net_stats += (s.net_read + s.net_write);
        }
        foreach (var s in stats) {
            io_stats += (s.disk_read + s.disk_write);
        }

        stats_updated ();
    }

    private uint stats_id;
    private void set_stats_enable (bool enable) {
        if (enable) {
            if (stats_id != 0)
                return;

            stats_id = Timeout.add_seconds (1, () => {
                update_stats ();
                return true;
            });
        } else {
            if (stats_id != 0)
                GLib.Source.remove (stats_id);
            stats_id = 0;
        }
    }

    public override List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Pair<string, Widget>> ();

        switch (page) {
        case PropertiesPage.LOGIN:
            add_string_property (ref list, _("Virtualizer"), source.uri);
            add_string_property (ref list, _("URI"), display.uri);
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

        return_if_fail (_connect_display == true);

        try {
            var xmldoc = domain.get_config (0).to_xml();
            type = extract_xpath (xmldoc, "string(/domain/devices/graphics/@type)", true);
            port = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@port)");
            socket = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@socket)");
            host = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@listen)");
        } catch (GLib.Error error) {
            warning (error.message);
            return;
        }

        if (display != null)
            display.disconnect_it ();

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

    public override bool is_running () {
        return state == DomainState.RUNNING;
    }

    public override async bool take_screenshot () throws GLib.Error {
        if (state != DomainState.RUNNING &&
            state != DomainState.PAUSED)
            return true;

        var stream = connection.get_stream (0);
        var file_name = get_screenshot_filename ();
        var file = File.new_for_path (file_name);
        var output_stream = yield file.replace_async (null, false, FileCreateFlags.REPLACE_DESTINATION);
        var input_stream = stream.get_input_stream ();
        domain.screenshot (stream, 0, 0);

        var buffer = new uint8[65535];
        ssize_t length = 0;
        do {
            length = yield input_stream.read_async (buffer);
            yield output_stream_write (output_stream, buffer[0:length]);
        } while (length > 0);

        return true;
    }

    public override void delete (bool by_user = true) {
        if (by_user) {
            try {
                // The reason we fetch the volume before stopping the domain is that we need the domain's
                // configuration for fechting its volume and transient domains stop existing after they are stopped.
                // OTOH we can't just delete the volume from a running domain.
                var volume = get_storage_volume ();

                try {
                    if (is_running ())
                        domain.stop (0);
                } catch (GLib.Error err) {
                    // ignore stop error
                }

                if (volume != null)
                    volume.delete (0);
                if (domain.persistent)
                    domain.delete (0);
            } catch (GLib.Error err) {
                warning (err.message);
            }
        }

        set_stats_enable (false);
    }

    public async void suspend () throws GLib.Error {
        (save_on_quit) ? yield domain.save_async (0, null) : domain.suspend ();
    }

    private GVir.StorageVol? get_storage_volume () throws GLib.Error {
        if (connection != app.default_connection)
            return null;

        var config = domain.get_config (0);
        var pool = connection.find_storage_pool_by_name (Config.PACKAGE_TARNAME);
        if (pool == null)
            // Absence of our pool just means that disk was not created by us and therefore should not be deleted by
            // us either.
            return null;

        foreach (var device in config.get_devices ()) {
            if (!(device is GVirConfig.DomainDisk))
                continue;

            var path = (device as GVirConfig.DomainDisk).get_source ();

            foreach (var volume in pool.get_volumes ())
                if (volume.get_path () == path)
                    return volume;
        }

        return null;
    }
}
