// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;
using Gtk;

private class Boxes.LibvirtMachine: Boxes.Machine {
    public GVir.Domain domain;
    public GVirConfig.Domain domain_config;
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
        if (display == null)
            return;

        app.display_page.remove_display ();
        display.disconnect_it ();
        display = null;
    }

    private ulong started_id;
    public override void connect_display () {
        if (display != null)
            return;

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

    static const int STATS_SIZE = 20;
    private MachineStat[] stats;
    construct {
        stats = new MachineStat[STATS_SIZE];
    }

    public void update_domain_config () {
        try {
            this.domain_config = domain.get_config (0);
        } catch (GLib.Error error) {
            critical ("Failed to fetch configuration for domain '%s': %s", domain.get_name (), error.message);
        }
    }

    public LibvirtMachine (CollectionSource source,
                           Boxes.App app,
                           GVir.Connection connection,
                           GVir.Domain domain) throws GLib.Error {
        base (source, app, domain.get_name ());

        debug ("new libvirt machine: " + name);
        this.config = new DisplayConfig (source, domain.get_uuid ());
        this.connection = connection;
        this.domain = domain;
        this.domain_config = domain.get_config (0);

        domain.updated.connect (update_domain_config);

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
            var xmldoc = domain_config.to_xml ();
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
            var xmldoc = domain_config.to_xml ();
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

        foreach (var stat in stats) {
            cpu_stats += stat.cpu_guest_percent;
            net_stats += (stat.net_read + stat.net_write);
            io_stats += (stat.disk_read + stat.disk_write);
        }

        stats_updated ();
    }

    private uint stats_id;
    private void set_stats_enable (bool enable) {
        if (enable) {
            debug ("enable statistics for " + name);
            if (stats_id != 0)
                return;

            stats_id = Timeout.add_seconds (1, () => {
                update_stats ();
                return true;
            });
        } else {
            debug ("disable statistics for " + name);
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
        debug ("delete libvirt machine: " + name);
        base.delete (by_user);

        set_stats_enable (false);

        if (by_user) {
            try {
                if (is_running ())
                    domain.stop (0);
            } catch (GLib.Error err) {
                // ignore stop error
            }

            try {
                if (connection == app.default_connection) {
                    var volume = get_storage_volume (connection, domain);
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
}
