// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;
using Gtk;

private class Boxes.LibvirtMachine: Boxes.Machine {
    public GVir.Domain domain { get; set; }
    public GVirConfig.Domain domain_config { get; set; }
    public GVir.Connection connection { get; set; }
    public GVir.StorageVol? storage_volume { get; set; }
    private VMCreator? _vm_creator;
    public VMCreator? vm_creator { // Under installation if this is set to non-null
        get {
            return _vm_creator;
        }

        set {
            _vm_creator = value;
            can_delete = !importing;
            under_construction = (value != null && !VMConfigurator.is_live_config (domain_config));
            notify_property ("importing");
            if (value == null)
                update_domain_config ();
            update_status ();
        }
    }
    // If this machine is currently being imported
    public bool importing { get { return vm_creator != null && vm_creator is VMImporter; } }

    public LibvirtMachineProperties properties;

    public bool save_on_quit {
        get { return source.get_boolean ("source", "save-on-quit"); }
        set { source.set_boolean ("source", "save-on-quit", value); }
    }

    public override bool suspend_at_exit { get { return connection == App.app.default_connection && !run_in_bg; } }
    public override bool can_save { get { return !saving && state != MachineState.SAVED && !importing; } }
    public override bool can_restart { get { return state == MachineState.RUNNING || state == MachineState.SAVED; } }
    public override bool can_clone { get { return !importing; } }
    protected override bool should_autosave {
        get {
            return (base.should_autosave &&
                    connection == App.app.default_connection &&
                    !run_in_bg &&
                    vm_creator == null);
        }
    }

    public bool run_in_bg { get; set; } // If true, machine will never be paused automatically by Boxes.

    public override bool is_local {
        get {
            // If the URI is prefixed by "qemu" or "qemu+unix" and the domain is "system" of "session" then it is local.
            if (/^qemu(\+unix)?:\/\/\/(system|session)/i.match (source.uri))
                return true;

            return base.is_local;
        }
    }

    public override void disconnect_display () {
        stay_on_display = false;

        base.disconnect_display ();
    }

    public override async void connect_display (Machine.ConnectFlags flags) throws GLib.Error {
        connecting_cancellable.reset ();

        yield wait_for_save ();

        if (connecting_cancellable.is_cancelled ()) {
            connecting_cancellable.reset ();

            return;
        }

        yield start (flags, connecting_cancellable);
        if (connecting_cancellable.is_cancelled ()) {
            connecting_cancellable.reset ();

            return;
        }

        if (update_display ()) {
            Display.OpenFDFunc? open_fd = null;

            if (source.uri.has_prefix ("qemu+unix"))
                open_fd = () => {
                    try {
                        return domain.open_graphics_fd (0, 0);
                    } catch (GLib.Error error) {
                        critical ("Failed to open graphics for %s: %s", name, error.message);

                        return -1;
                    }
                };

            display.connect_it ((owned) open_fd);
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

    const int STATS_SIZE = 20;
    private MachineStat[] stats;

    private bool force_stopped;
    private bool saving; // Machine is being saved currently..

    private GVir.Connection system_virt_connection;

    private BoxConfig.SavedProperty[] saved_properties;

    construct {
        stats = new MachineStat[STATS_SIZE];
        stats_cancellable = new Cancellable ();
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

        var current_window = this.window;
        disconnect_display ();
        this.window = current_window;
        connect_display.begin (Machine.ConnectFlags.NONE);
    }

    public async LibvirtMachine (CollectionSource source,
                                 GVir.Connection connection,
                                 GVir.Domain     domain) throws GLib.Error {
        var config = domain.get_config (GVir.DomainXMLFlags.INACTIVE);
        var item_name = config.get_title () ?? domain.get_name ();
        base (source, item_name, domain.get_uuid ());

        debug ("new libvirt machine: " + domain.get_name ());
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

        try {
            system_virt_connection = yield get_system_virt_connection ();
        } catch (GLib.Error error) {
            warning ("Failed to connection to system libvirt: %s", error.message);
        }

        update_status ();
        update_info ();
        source.notify["uri"].connect (update_info);

        saved_properties = {
            BoxConfig.SavedProperty () { name = "run-in-bg", default_value = false },
        };

        this.config.save_properties (this, saved_properties);
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

            yield App.app.async_launcher.launch ( () => {
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

            yield App.app.async_launcher.launch ( () => {
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

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page) {
        var list = properties.get_properties (page);

        if (display != null)
            list.concat (display.get_properties (page));

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
        string type, port_str, socket, host;

        var xmldoc = domain_config.to_xml ();
        type = extract_xpath (xmldoc, "string(/domain/devices/graphics/@type)", true);
        port_str = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@port)");
        socket = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@socket)");
        host = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@listen)");
        var port = int.parse (port_str);

        if (host == null || host == "")
            host = "localhost";

        switch (type) {
        case "spice":
            if (port > 0)
                return new SpiceDisplay (this, config, host, port);
            else
                return new SpiceDisplay.priv (this, config);

        case "vnc":
            return new VncDisplay (config, host, port);

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
        yield App.app.async_launcher.launch (()=> {
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
            App.app.async_launcher.launch.begin ( () => {
                try {
                    // This undefines the domain, causing it to be transient if it was running
                    domain.delete (DomainDeleteFlags.SAVED_STATE |
                                   DomainDeleteFlags.SNAPSHOTS_METADATA);
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
        saving = true;
        yield domain.save_async (0, null);
        saving = false;
    }

    public async void suspend () throws GLib.Error {
        if (save_on_quit)
            yield save ();
        else
            domain.suspend ();
    }

    public void force_shutdown () {
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
                window.topbar.status = _("Restoring %s from disk").printf (name);
            else
                // Translators: The %s will be expanded with the name of the vm
                 window.topbar.status = _("Starting %s").printf (name);
            try {
                yield domain.start_async (connect_flags_to_gvir (flags), cancellable);
            } catch (IOError.CANCELLED error) {
                debug ("starting of %s was cancelled", name);
            } catch (GLib.Error error) {
                if (restore)
                    throw new Boxes.Error.RESTORE_FAILED (error.message);
                else
                    throw new Boxes.Error.START_FAILED (error.message);
            }

            if (restore) {
                try {
                    yield domain.set_time_async (null, 0, null);
                } catch (GLib.Error error) {
                    debug ("Failed to update clock on %s: %s", name, error.message);
                }
            }
        }
    }

    public override void restart () {
        if (state == Machine.MachineState.SAVED) {
            debug ("'%s' is in saved state. Resuming it..", name);
            start.begin (Machine.ConnectFlags.NONE, null, (obj, res) => {
                try {
                    start.end (res);
                    restart ();
                } catch (GLib.Error error) {
                    warning ("Failed to start '%s': %s", domain.get_name (), error.message);
                }
            });

            return;
        }

        stay_on_display = true;
        ulong state_id = 0;
        Boxes.Notification notification = null;
        debug ("Rebooting '%s'..", name);

        state_id = notify["state"].connect (() => {
            if (state == Machine.MachineState.STOPPED ||
                state == Machine.MachineState.FORCE_STOPPED) {
                debug ("'%s' stopped.", name);
                start.begin (Machine.ConnectFlags.NONE, null, (obj, res) => {
                    try {
                        start.end (res);
                    } catch (GLib.Error error) {
                        warning ("Failed to start '%s': %s", domain.get_name (), error.message);
                    }
                });

                disconnect (state_id);
                if (shutdown_timeout != 0) {
                    Source.remove (shutdown_timeout);
                    shutdown_timeout = 0;
                }
                if (notification != null) {
                    notification.dismiss ();
                    notification = null;
                }
            }
        });

        shutdown_timeout = Timeout.add_seconds (5, () => {
            // Seems guest ignored ACPI shutdown, lets force shutdown with user's consent
            Notification.OKFunc really_force_shutdown = () => {
                notification = null;
                force_shutdown ();
            };

            var message = _("Restart of “%s” is taking too long. Force it to shutdown?").printf (name);
            notification = window.notificationbar.display_for_action (message,
                                                                       _("_Shutdown"),
                                                                       (owned) really_force_shutdown,
                                                                       null,
                                                                       -1);
            shutdown_timeout = 0;

            return false;
        });

        try_shutdown ();
    }

    public override async void clone () {
        debug ("Cloning '%s'..", domain_config.name);
        can_delete = false;

        var inhibit_reason = _("Cloning '%s'..").printf (domain_config.name);
        App.app.inhibit (null, null, inhibit_reason);

        try {
            // Any better way of cloning the config?
            var xml = domain_config.to_xml ();
            var config = new GVirConfig.Domain.from_xml (xml);
            config.set_uuid (null);

            var media = new LibvirtClonedMedia (storage_volume.get_path (), config);
            var vm_cloner = media.get_vm_creator ();
            var clone_machine = yield vm_cloner.create_vm (null);
            vm_cloner.launch_vm (clone_machine, this.config.access_last_time);

            ulong under_construct_id = 0;
            under_construct_id = clone_machine.notify["under-construction"].connect (() => {
                if (!clone_machine.under_construction) {
                    can_delete = true;
                    clone_machine.disconnect (under_construct_id);

                    App.app.uninhibit ();
                }
            });
        } catch (GLib.Error error) {
            warning ("Failed to clone %s: %s", domain_config.name, error.message);
            can_delete = true;
        }
    }

    public string? get_ip_address () {
        if (system_virt_connection == null || !is_on)
            return null;

        var mac = get_mac_address ();
        if (mac == null)
            return null;
        debug ("MAC address of '%s': %s", name, mac);

        foreach (var network in system_virt_connection.get_networks ()) {
            try {
                var leases = network.get_dhcp_leases (mac, 0);

                if (leases.length () == 0 || leases.data.get_iface () != "virbr0")
                    continue;
                debug ("Found a lease for '%s' on network '%s'", name, network.get_name ());

                // Get first IP in the list
                return leases.data.get_ip ();
            } catch (GLib.Error error) {
                warning ("Failed to get DHCP leases from network '%s': %s",
                         network.get_name (),
                         error.message);
            }
        }
        debug ("No lease for '%s' on any network", name);

        return null;
    }

    public async GVir.DomainSnapshot create_snapshot (string description_prefix = "") throws GLib.Error {
        var config = new GVirConfig.DomainSnapshot ();
        var now = new GLib.DateTime.now_local ();
        config.set_name (now.format ("%F-%H-%M-%S"));
        config.set_description (description_prefix + now.format ("%x, %X"));

        return yield domain.create_snapshot_async (config, 0, null);
    }

    private async void wait_for_save () {
        if (!saving)
            return;

        var state_notify_id = notify["state"].connect (() => {
            if (state == MachineState.SAVED)
                wait_for_save.callback ();
        });
        var cancelled_id = connecting_cancellable.cancelled.connect (() => {
            Idle.add (() => {
                // This callback is synchronous and calling it directly from cancelled callback will mean
                // disconnecting from this signal and resetting cancellable from right here and that seems to hang
                // the application.
                wait_for_save.callback ();

                return false;
            });
        });

        debug ("%s is being saved, delaying starting until it's saved", name);
        yield;

        disconnect (state_notify_id);
        connecting_cancellable.disconnect (cancelled_id);
    }

    protected override void update_status () {
        base.update_status ();

        if (status != null)
            return;

        if (VMConfigurator.is_install_config (domain_config))
            status = _("Installing…");
        else if (VMConfigurator.is_live_config (domain_config))
            status = _("Live");
        else if (VMConfigurator.is_libvirt_cloning_config (domain_config))
            status = _("Setting up clone…");
        else if (VMConfigurator.is_import_config (domain_config))
            status = _("Importing…");
        else
            status = null;
    }

    private void update_info () {
        if (!is_local) {
            var uri = Xml.URI.parse (source.uri);

            info = _("host: %s").printf (uri.server);
        } else
            info = null;
    }

    private string? get_mac_address () {
        GVirConfig.DomainInterface? iface_config = null;

        foreach (var device_config in domain_config.get_devices ()) {
            // Only entertain bridge network. With user networking, the IP address isn't even reachable from host so
            // it's pretty much useless to show that to user.
            if (device_config is GVirConfig.DomainInterfaceBridge) {
                iface_config = device_config as GVirConfig.DomainInterface;

                break;
            }
        }

        if (iface_config == null)
            return null;

        return iface_config.get_mac ().dup ();
    }
}
