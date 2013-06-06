// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;
using Gtk;

private class Boxes.LibvirtMachine: Boxes.Machine {
    public GVir.Domain domain { get; set; }
    public GVirConfig.Domain domain_config { get; set; }
    public GVir.Connection connection { get; set; }
    public GVir.StorageVol? storage_volume { get; set; }
    public VMCreator? vm_creator { get; set; } // Under installation if this is set to non-null
    // If this machine is currently being imported
    public bool importing { get { return vm_creator != null && vm_creator is VMImporter; } }

    private LibvirtMachineProperties properties;

    public bool save_on_quit {
        get { return source.get_boolean ("source", "save-on-quit"); }
        set { source.set_boolean ("source", "save-on-quit", value); }
    }

    public override void disconnect_display () {
        stay_on_display = false;

        base.disconnect_display ();
    }

    public override async void connect_display (Machine.ConnectFlags flags) throws GLib.Error {
        connecting_cancellable.reset ();

        yield start (flags, connecting_cancellable);
        if (connecting_cancellable.is_cancelled ()) {
            connecting_cancellable.reset ();

            return;
        }

        if (update_display ()) {
            display.connect_it ();
        } else {
            show_display ();
            display.set_enable_audio (true);
        }
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

    private uint shutdown_timeout;

    private uint stats_update_timeout;
    private Cancellable stats_cancellable;

    static const int STATS_SIZE = 20;
    private MachineStat[] stats;

    private bool force_stopped;

    construct {
        stats = new MachineStat[STATS_SIZE];
        stats_cancellable = new Cancellable ();
        can_save = true;
    }

    public void update_domain_config () {
        try {
            domain_config = domain.get_config (GVir.DomainXMLFlags.NONE);
            storage_volume = get_storage_volume (connection, domain);
        } catch (GLib.Error error) {
            critical ("Failed to fetch configuration for domain '%s': %s", domain.get_name (), error.message);
        }
    }

    private void reconnect_display () {
        // If we haven't connected yet, don't reconnect
        if (display == null)
            return;

        disconnect_display ();
        connect_display.begin (Machine.ConnectFlags.NONE);
    }

    public LibvirtMachine (CollectionSource source,
                           GVir.Connection connection,
                           GVir.Domain     domain) throws GLib.Error {
        var config = domain.get_config (GVir.DomainXMLFlags.INACTIVE);
        var item_name = config.get_title () ?? domain.get_name ();
        base (source, item_name);

        debug ("new libvirt machine: " + domain.get_name ());
        create_display_config (domain.get_uuid ());
        this.connection = connection;
        this.domain = domain;
        this.properties = new LibvirtMachineProperties (this);

        try {
            var s = domain.get_info ().state;
            switch (s) {
            case DomainState.RUNNING:
            case DomainState.BLOCKED:
                state = MachineState.RUNNING;
                set_stats_enable (true);
                break;
            case DomainState.PAUSED:
                state = MachineState.PAUSED;
                break;
            case DomainState.SHUTDOWN:
            case DomainState.SHUTOFF:
                if (domain.get_saved ())
                    state = MachineState.SAVED;
                else
                    state = MachineState.STOPPED;
                break;
            case DomainState.CRASHED:
                state = MachineState.STOPPED;
                break;
            case DomainState.PMSUSPENDED:
                state = MachineState.SLEEPING;
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
        domain.stopped.connect (() => {
            if (Signal.get_invocation_hint (this.domain).detail == Quark.from_string ("saved"))
                state = MachineState.SAVED;
            else if (force_stopped) {
                force_stopped = false;
                state = MachineState.FORCE_STOPPED;
            } else
                state = MachineState.STOPPED;
        });
        domain.pmsuspended.connect (() => {
            state = MachineState.SLEEPING;
        });
        notify["state"].connect (() => {
            if (state == MachineState.RUNNING) {
                reconnect_display ();
                set_stats_enable (true);
            } else
                set_stats_enable (false);
        });

        update_domain_config ();
        domain.updated.connect (update_domain_config);

        if (state != MachineState.STOPPED)
            load_screenshot ();
        set_screenshot_enable (true);
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

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page, ref PropertyCreationFlag flags) {
        var list = properties.get_properties (page, ref flags);

        if (display != null)
            list.concat (display.get_properties (page,
                                                 ref flags));

        return list;
    }

    public bool update_display () throws GLib.Error {
        update_domain_config ();

        var created_display = display == null;
        if (display == null)
            display = create_display ();
        return created_display;
    }

    private Display? create_display () throws Boxes.Error {
        string type, port, socket, host;

        var xmldoc = domain_config.to_xml ();
        type = extract_xpath (xmldoc, "string(/domain/devices/graphics/@type)", true);
        port = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@port)");
        socket = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@socket)");
        host = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@listen)");

        if (host == null || host == "")
            host = "localhost";

        switch (type) {
        case "spice":
            return new SpiceDisplay (config, host, int.parse (port));

        case "vnc":
            return new VncDisplay (config, host, int.parse (port));

        default:
            throw new Boxes.Error.INVALID ("unsupported display of type " + type);
        }
    }

    protected override async Gdk.Pixbuf? take_screenshot () throws GLib.Error {
        var state = DomainState.NONE;
        try {
            state = (yield domain.get_info_async (null)).state;
        } catch (GLib.Error error) {
            warning ("Failed to get information on '%s'", name);
        }

        if (state != DomainState.RUNNING && state != DomainState.PAUSED && state != DomainState.PMSUSPENDED)
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
        if (shutdown_timeout != 0) {
            Source.remove (shutdown_timeout);
            shutdown_timeout = 0;
        }

        if (by_user) {
            var domain = this.domain; // Don't reference self in thread

            /* Run all the slow operations in a separate thread
               to avoid blocking the UI */
            run_in_thread.begin ( () => {
                try {
                    // This undefines the domain, causing it to be transient if it was running
                    domain.delete (DomainDeleteFlags.SAVED_STATE);
                } catch (GLib.Error err) {
                    warning (err.message);
                }

                try {
                    // Ensure that the domain is stopped before we touch any data
                    domain.stop (0);
                } catch (GLib.Error err) {
                    debug (err.message); // No warning cause this can easily fail for legitimate reasons
                }

                // Remove any images controlled by boxes
                if (storage_volume != null)
                    try {
                        storage_volume.delete (0);
                    } catch (GLib.Error err) {
                        warning (err.message);
                    }
            });
        }
    }

    public async override void save_real () throws GLib.Error {
        yield domain.save_async (0, null);
    }

    public async void suspend () throws GLib.Error {
        if (save_on_quit)
            yield save ();
        else
            domain.suspend ();
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
            force_stopped = true;
            domain.stop (0);
        } catch (GLib.Error error) {
            warning ("Failed to shutdown '%s': %s", domain.get_name (), error.message);
        }
    }

    public void try_shutdown () {
        try {
            domain.shutdown (0);
        } catch (GLib.Error error) {
            warning ("Failed to reboot '%s': %s", domain.get_name (), error.message);
        }
    }

    public GVir.DomainDisk? get_domain_disk () throws GLib.Error {
        var disk = null as GVir.DomainDisk;

        foreach (var device_config in domain_config.get_devices ()) {
            if (device_config is GVirConfig.DomainDisk) {
                var disk_config = device_config as GVirConfig.DomainDisk;
                var disk_type = disk_config.get_guest_device_type ();
                var storage_volume_path = (storage_volume != null)? storage_volume.get_path () : null;

                // Prefer Boxes' managed volume over other disks
                if (disk_type == GVirConfig.DomainDiskGuestDeviceType.DISK &&
                    disk_config.get_source () == storage_volume_path) {
                    disk = Object.new (typeof (GVir.DomainDisk),
                                       "domain", domain,
                                       "config", device_config) as GVir.DomainDisk;

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
                net = Object.new (typeof (GVir.DomainInterface),
                                  "domain", domain,
                                  "config", device_config) as GVir.DomainInterface;
                break;
            }
        }

        return net;
    }

    private GVir.DomainStartFlags connect_flags_to_gvir (Machine.ConnectFlags flags) {
        GVir.DomainStartFlags gvir_flags = 0;
        if (Machine.ConnectFlags.IGNORE_SAVED_STATE in flags)
            gvir_flags |= GVir.DomainStartFlags.FORCE_BOOT;
        return gvir_flags;
    }

    public async void start (Machine.ConnectFlags flags, Cancellable? cancellable = null) throws GLib.Error {
        if (state == MachineState.RUNNING)
            return;

        if (state == MachineState.PAUSED)
            yield domain.resume_async (cancellable);
        else if (state == MachineState.SLEEPING) {
            yield domain.wakeup_async (0, cancellable);
        } else {
            var restore = domain.get_saved () &&
                !(Machine.ConnectFlags.IGNORE_SAVED_STATE in flags);
            if (restore)
                // Translators: The %s will be expanded with the name of the vm
                status = _("Restoring %s from disk").printf (name);
            else
                // Translators: The %s will be expanded with the name of the vm
                status = _("Starting %s").printf (name);
            try {
                yield domain.start_async (connect_flags_to_gvir (flags), cancellable);
            } catch (IOError.CANCELLED error) {
                debug ("starting of %s was cancelled", name);
            } catch (GLib.Error error) {
                if (restore)
                    throw new Boxes.Error.RESTORE_FAILED ("Restore failed");
                else
                    throw error;
            }
        }
    }
}
