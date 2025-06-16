// This file is part of GNOME Boxes. License: LGPLv2+
using Config;

private abstract class Boxes.Broker : GLib.Object {
    // Overriding subclass should chain-up at the end of its implementation
    public virtual async void add_source (CollectionSource source) throws GLib.Error {
        var used_configs = new GLib.List<BoxConfig> ();
        for (int i = 0; i < App.app.collection.length; i++) {
            var item = App.app.collection.get_item (i);

            if (!(item is Machine))
                continue;

            var machine = item as Machine;
            used_configs.append (machine.config);
        }

        source.purge_stale_box_configs (used_configs);
    }
}

private class Boxes.App: Gtk.Application {
    public static App app;

    public const string DEFAULT_SOURCE_NAME = "QEMU Session";

    private List<Boxes.AppWindow> windows;
    private List<string> system_notifications;

    public unowned AppWindow main_window {
        get { return (windows.length () > 0) ? windows.data : null; }
    }

    public string? uri { get; set; }
    public Collection collection;

    private bool is_ready;
    public signal void ready ();

    public bool run_in_bg {
        get; private set;
    }

    private static bool? is_flatpak;

    // A callback to notify that deletion of machines was undone by user.
    public delegate void UndoNotifyCallback ();

    private HashTable<string,Broker> brokers;
    private HashTable<string,CollectionSource> sources;
    public GVir.Connection default_connection { owned get { return LibvirtBroker.get_default ().get_connection ("QEMU Session"); } }
    public CollectionSource default_source { get { return sources.get (DEFAULT_SOURCE_NAME); } }
    public AsyncLauncher async_launcher;
    public SharedFoldersManager shared_folders_manager = SharedFoldersManager.get_default ();

    private uint inhibit_cookie = 0;

    public App () {
        application_id = Config.APPLICATION_ID;
        flags |= ApplicationFlags.HANDLES_COMMAND_LINE | ApplicationFlags.HANDLES_OPEN;
        resource_base_path = "/org/gnome/Boxes";

        app = this;
        async_launcher = AsyncLauncher.get_default ();
        windows = new List<Boxes.AppWindow> ();
        system_notifications = new List<string> ();
        sources = new HashTable<string,CollectionSource> (str_hash, str_equal);
        brokers = new HashTable<string,Broker> (str_hash, str_equal);
        var action = new GLib.SimpleAction ("quit", null);
        action.activate.connect (() => { quit_app (); });
        add_action (action);

        action = new GLib.SimpleAction ("help", null);
        action.activate.connect (() => {
            try {
                Gtk.show_uri_on_window (main_window, "help:gnome-boxes", Gtk.get_current_event_time ());
            } catch (GLib.Error e) {
                warning ("Failed to display help: %s", e.message);
            }
        });
        add_action (action);

        action = new GLib.SimpleAction ("launch-box", GLib.VariantType.STRING);
        action.activate.connect ((param) => { open_name (param.get_string ()); });
        add_action (action);

        action = new GLib.SimpleAction ("launch-run-in-bg-box", GLib.VariantType.STRING);
        action.activate.connect ((param) => { open_run_in_bg_vm (param.get_string ()); });
        add_action (action);

        action = new GLib.SimpleAction ("install", GLib.VariantType.STRING);
        action.activate.connect ((param) => { install (param.get_string ()); });
        add_action (action);

        action = new GLib.SimpleAction ("about", null);
        action.activate.connect (() => {
            string[] authors = {
                "Alexander Larsson <alexl@redhat.com>",
                "Christophe Fergeau <cfergeau@redhat.com>",
                "Marc-André Lureau <marcandre.lureau@gmail.com>",
                "Zeeshan Ali (Khattak) <zeeshanak@gnome.org>"
            };
            string[] artists = {
                "Allan Day <aday@gnome.org>",
                "Jon McCann <jmccann@redhat.com>",
                "Jakub Steiner <jsteiner@redhat.com>",
                "Dave Jones <eevblog@yahoo.com.au>"
            };

            Gtk.show_about_dialog (main_window,
                                   "artists", artists,
                                   "authors", authors,
                                   "translator-credits", _("translator-credits"),
                                   "comments", _("A simple GNOME application to access virtual systems"),
                                   "copyright", "\xc2\xa9 2011-2018 Red Hat, Inc.",
                                   "license-type", Gtk.License.LGPL_2_1,
                                   "program-name", _("Boxes") + Config.NAME_SUFFIX,
                                   "logo-icon-name", Config.APPLICATION_ID,
                                   "version", Config.VERSION,
                                   "website", Config.PACKAGE_URL,
                                   "wrap-license", true);
        });
        add_action (action);

        var webkit_context = WebKit.WebContext.get_default ();
        webkit_context.set_sandbox_enabled (true);
    }

    public override void startup () {
        base.startup ();

        Hdy.init ();

        string [] args = {};
        unowned string [] args2 = args;
        Gtk.init (ref args2);

        collection = new Collection ();

        brokers.insert ("libvirt", LibvirtBroker.get_default ());

        check_cpu_vt_capability.begin ();
        check_module_kvm_loaded.begin ();
    }

    public delegate void CallReadyFunc ();
    public void call_when_ready (owned CallReadyFunc func) {
        if (is_ready)
            func ();
        ready.connect (() => {
            func ();
        });
    }

    public override void activate () {
        base.activate ();

        if (main_window != null)
            return;

        var window = add_new_window ();
        window.set_state (UIState.COLLECTION);

        activate_async.begin ();

        window.show_welcome_tutorial ();
    }

    static bool opt_fullscreen;
    static bool opt_help;
    static string opt_open_uuid;
    static string[] opt_uris;
    [CCode (array_length=false, array_null_terminated=true)]
    static string[] opt_search;
    const OptionEntry[] options = {
        { "version", 0, 0, OptionArg.NONE, null, N_("Display version number"), null },
        { "help", 'h', 0, OptionArg.NONE, ref opt_help, N_("Show help"), null },
        { "full-screen", 'f', 0, OptionArg.NONE, ref opt_fullscreen, N_("Open in full screen"), null },
        { "checks", 0, 0, OptionArg.NONE, null, N_("Check virtualization capabilities"), null },
        { "open-uuid", 0, 0, OptionArg.STRING, ref opt_open_uuid, N_("Open box with UUID"), null },
        { "search", 0, 0, OptionArg.STRING_ARRAY, ref opt_search, N_("Search term"), null },
        // A 'broker' is a virtual-machine manager (local or remote). Currently only libvirt is supported.
        { "", 0, 0, OptionArg.STRING_ARRAY, ref opt_uris, N_("URL to display, broker or installer media"), null },
        { null }
    };

    public override int command_line (GLib.ApplicationCommandLine cmdline) {
        opt_fullscreen = false;
        opt_help = false;
        opt_open_uuid = null;
        opt_uris = null;
        opt_search = null;

        var parameter_string = _("— A simple application to access virtual machines");
        var opt_context = new OptionContext (parameter_string);
        opt_context.add_main_entries (options, null);
        opt_context.add_group (Spice.get_option_group ());
        opt_context.add_group (Gtk.get_option_group (true));
        opt_context.set_help_enabled (false);

        try {
            string[] args1 = cmdline.get_arguments();
            unowned string[] args2 = args1;
            opt_context.parse (ref args2);
        } catch (OptionError error) {
            cmdline.printerr ("%s\n", error.message);
            cmdline.printerr (opt_context.get_help (true, null));
            return 1;
        }

        if (opt_help) {
            cmdline.printerr (opt_context.get_help (true, null));
            return 1;
        }

        if (opt_uris.length > 1 ||
            (opt_open_uuid != null && opt_uris != null)) {
            cmdline.printerr (_("Too many command line arguments specified.\n"));
            cmdline.printerr (opt_context.get_help (true, null));
            return 1;
        }

        activate ();

        var app = this;
        if (opt_open_uuid != null) {
            var uuid = opt_open_uuid;
            call_when_ready (() => {
                    app.open_uuid (uuid);
            });
        } else if (opt_uris != null) {
            var arg = opt_uris[0];

            call_when_ready (() => {
                var file = File.new_for_commandline_arg (arg);

                if (file.query_exists ())
                    main_window.show_vm_assistant (file.get_path ());
                else
                    open_name (arg);
            });
        }

        if (opt_search != null) {
            call_when_ready (() => {
                main_window.searchbar.text = string.joinv (" ", opt_search);
                if (main_window.ui_state == UIState.COLLECTION)
                    main_window.searchbar.search_mode_enabled = true;
            });
        }

        if (opt_fullscreen)
            main_window.fullscreened = true;

        return 0;
    }

    public override void open (File[] _files, string hint) {
        activate ();

        File[] files = _files;
        call_when_ready (() => {
            foreach (File file in files) {
                main_window.show_vm_assistant (file.get_path ());
            }
        });
    }

    public bool quit_app () {
        foreach (var window in windows)
            window.hide ();
        // Ensure windows are hidden before returning from this function
        var display = Gdk.Display.get_default ();
        display.flush ();

        keep_on_running_on_background ();
        if (run_in_bg)
            return true;

        Idle.add (() => {
            quit ();

            return false;
        });

        return true;
    }

    public override void shutdown () {
        if (!run_in_bg) {
            base.shutdown ();

            // Withdraw all the existing notifications
            foreach (var notification in system_notifications)
                withdraw_notification (notification);
        } else {
            this.hold ();
        }

        main_window.dismiss_toast ();

        async_launcher.await_all ();
        suspend_machines ();
    }

    private void open_run_in_bg_vm (string name) {
        activate ();

        main_window.present ();
        call_when_ready (() => {
            open_name (name);
        });

    }

    public void open_name (string name) {
        main_window.set_state (UIState.COLLECTION);

        // after "ready" all items should be listed
        for (int i = 0 ; i < collection.length ; i++) {
            var item = collection.get_item (i);

            if (item.name == name) {
                main_window.select_item (item);

                break;
            }
        }
    }

    public void install (string path) {
        main_window.show_vm_assistant (path);
    }

    public bool open_uuid (string uuid) {
        main_window.set_state (UIState.COLLECTION);

        // after "ready" all items should be listed
        for (int i = 0 ; i < collection.length ; i++) {
            var item = collection.get_item (i);

            if (!(item is Boxes.Machine))
                continue;
            var machine = item as Boxes.Machine;

            if (machine.config.uuid != uuid)
                continue;

            main_window.select_item (item);
            return true;
        }

        return false;
    }

    public void open_in_new_window (Machine machine) {
        if (machine.window != main_window) {
            machine.window.present ();

            return;
        }

        // machine.window == main_window could just mean machine is not running on any window so lets make sure..
        if (machine.ui_state == UIState.DISPLAY)
            machine.window.set_state (UIState.COLLECTION);

        var window = add_new_window ();
        window.connect_to (machine);
    }

    public void delete_machine (Machine machine, bool by_user = true) {
        machine.delete (by_user);         // Will also delete associated storage volume if by_user is 'true'
        collection.remove_item (machine);
    }

    public async void add_collection_source (CollectionSource source) throws GLib.Error {
        if (!source.enabled)
            return;

        if (sources.get (source.name) != null) {
            debug ("Attempt to add duplicate collection source '%s', ignoring..", source.name);
            return; // Already added
        }

        Broker? broker = brokers.lookup (source.source_type);
        if (broker != null) {
            yield broker.add_source (source);
            sources.insert (source.name, source);
            if (source.name == DEFAULT_SOURCE_NAME) {
                notify_property ("default-connection");
                notify_property ("default-source");
            }
        } else {
            warning ("Unsupported source type %s", source.source_type);
        }
    }

    private async void activate_async () {
        yield move_configs_from_cache ();

        yield setup_default_source ();

        is_ready = true;
        ready ();

        setup_sources.begin ();
    }

    private async void setup_default_source () ensures (default_connection != null) {
        var path = get_user_pkgconfig_source (DEFAULT_SOURCE_NAME);
        var create_session_source = true;
        try {
            var file = File.new_for_path (path);
            var info = yield file.query_info_async (FileAttribute.STANDARD_SIZE,
                                                    FileQueryInfoFlags.NONE,
                                                    Priority.DEFAULT,
                                                    null);
            create_session_source = (info.get_attribute_uint64 (FileAttribute.STANDARD_SIZE) <= 0);
        } catch (GLib.Error error) {
            debug ("Failed to query '%s': %s. Assuming it doesn't exist.", path, error.message);
        }

        if (create_session_source) {
            var src = File.new_for_path (get_pkgdata_source ("QEMU_Session"));
            var dst = File.new_for_path (path);
            try {
                yield src.copy_async (dst, FileCopyFlags.OVERWRITE | FileCopyFlags.TARGET_DEFAULT_PERMS);
            } catch (GLib.Error error) {
                critical ("Can't setup default sources: %s", error.message);
            }
        }

        try {
            var source = new CollectionSource.with_file (DEFAULT_SOURCE_NAME);
            yield add_collection_source (source);
        } catch (GLib.Error error) {
            printerr ("Error setting up default broker: %s\n", error.message);

            main_window.set_state (UIState.TROUBLESHOOT);

            return;
        }
    }

    public new void send_notification (string notification_id, GLib.Notification notification) {
        base.send_notification (notification_id, notification);

        system_notifications.append (notification_id);
    }

    public void notify_machine_installed (Machine machine) {
        if (machine.window.is_active) {
            debug ("Window is focused, no need for system notification");

            return;
        }

        var msg = _("Box “%s” installed and ready to use").printf (machine.name);
        var notification = new GLib.Notification (msg);
        notification.add_button (_("Launch"), "app.launch-box::" + machine.name);

        send_notification ("installed-" + machine.name, notification);
    }

    private async void setup_sources () {
        var dir = File.new_for_path (get_user_pkgconfig_source ());
        var new_sources = new GLib.List<CollectionSource> ();
        yield foreach_filename_from_dir (dir, (filename) => {
            if (filename == DEFAULT_SOURCE_NAME)
                return false;

            var source = new CollectionSource.with_file (filename);
            new_sources.append (source);
            return false;
        });

        foreach (var source in new_sources) {
            try {
                yield add_collection_source (source);
            } catch (GLib.Error error) {
                warning ("Failed to add '%s': %s", source.name, error.message);
            }
        }
    }

    private void notify_vm_is_running_in_background (LibvirtMachine machine) {
        if (!machine.run_in_bg && !machine.is_running)
            return;

        var msg = _("“%s“ is running in the background").printf (machine.name);
        var notification = new GLib.Notification (msg);
        notification.set_default_action ("app.launch-run-in-bg-box::" + machine.name);

        send_notification ("gnome-boxes-run-in-bg-%s" + machine.name, notification);
    }

    private void keep_on_running_on_background () {
        if (collection == null)
            return;

        run_in_bg = false;
        collection.foreach_item((item) => {
            var machine = item as LibvirtMachine;

            var keep_vm_running = (machine.run_in_bg && machine.is_running);
            if (keep_vm_running) {
                run_in_bg = is_running_in_flatpak ();

                notify_vm_is_running_in_background (machine);
                debug ("Keep running %s in the background", machine.name);
            }
        });
    }

    private void suspend_machines () {
        // if we are not the main Boxes instance, 'collection' won't
        // be set as it's created in GtkApplication::startup()
        if (collection == null)
            return;

        debug ("Suspending running boxes");

        var waiting_counter = 0;
        // use a private main context to suspend the VMs to avoid
        // DBus or other callbacks being fired while we suspend
        // the VMs during Boxes shutdown.
        var context = new MainContext ();

        context.push_thread_default ();
        collection.foreach_item ((item) => {
            if (item is LibvirtMachine) {
                var machine = item as LibvirtMachine;

                if (machine.suspend_at_exit) {
                    waiting_counter++;
                    machine.suspend.begin (() => {
                        debug ("%s suspended", machine.name);
                        waiting_counter--;
                    });
                }
            }
        });
        context.pop_thread_default ();

        // wait for async methods to complete
        while (waiting_counter > 0)
            context.iteration (true);

        debug ("Running boxes suspended");
    }

    /**
     * Deletes specified items, while allowing user to undo it.
     *
     * @param items the list of machines
     * @param message optional message to be shown together with the undo button. If not provided, an appropriate
     *                messsage is created.
     * @param callback optional function that, if provided, is called after the undo operation
     *
     * @attention the ownership for items is required since GLib.List is a compact class.
     */
    public void delete_machines_undoable (owned List<CollectionItem> items,
                                          string?                    message = null,
                                          owned UndoNotifyCallback?  undo_notify_callback = null) {
        var num_items = items.length ();
        if (num_items == 0)
            return;

        var msg = message;
        if (msg == null)
            msg = (num_items == 1) ? _("Box “%s” has been deleted").printf (items.data.name) :
                                     ngettext ("%u box has been deleted",
                                               "%u boxes have been deleted",
                                               num_items).printf (num_items);
        foreach (var item in items)
            collection.remove_item (item);

        Toast.OKFunc undo = () => {
            debug ("Box deletion cancelled by user. Re-adding to view");
            foreach (var item in items) {
                var machine = item as Machine;
                collection.add_item (machine);
            }
            if (undo_notify_callback != null)
                undo_notify_callback ();
        };

        Toast.DismissFunc really_remove = () => {
            debug ("User did not cancel deletion. Deleting now...");
            foreach (var item in items) {
                if (!(item is Machine))
                    continue;

                // Will also delete associated storage volume if by_user is 'true'
                var machine = item as Machine;
                machine.delete (true);
            }
        };

        main_window.display_toast (new Boxes.Toast () {
            message = msg,
            action = _("Undo"),
            undo_func = (owned) undo,
            dismiss_func = (owned) really_remove,
        });
    }

    public AppWindow add_new_window () {
        var window = new Boxes.AppWindow (this);

        windows.append (window);
        window.setup_ui ();
        window.present ();

        notify_property ("main-window");

        return window;
    }

    public new bool remove_window (AppWindow window) {
        if (windows.length () == 1)
            return quit_app ();

        var initial_windows_count = windows.length ();

        if (window.current_item != null) {
            var current_machine = window.current_item as Machine;
            current_machine.window = null;
        }

        window.hide ();

        windows.remove (window);
        base.remove_window (window);

        notify_property ("main-window");

        return initial_windows_count != windows.length ();
    }

    public new void inhibit (Gtk.Window? window = main_window, Gtk.ApplicationInhibitFlags? flags = null, string? reason = null) {
        if (reason == null) {
            reason = _("Boxes is doing something");
        }

        if (flags == null) {
            flags = Gtk.ApplicationInhibitFlags.IDLE | Gtk.ApplicationInhibitFlags.SUSPEND;
        }

        uint new_cookie = base.inhibit (window, flags, reason);
        if (inhibit_cookie != 0) {
            base.uninhibit (inhibit_cookie);
        }

        inhibit_cookie = new_cookie;
    }

    public new void uninhibit () {
        if (inhibit_cookie != 0) {
            base.uninhibit (inhibit_cookie);
        }
    }

    public static bool is_running_in_flatpak () {
        if (is_flatpak != null)
            return is_flatpak;

        var file = File.new_for_path ("/.flatpak-info");
        is_flatpak = file.query_exists ();

        return is_flatpak;
    }

    public bool supports_uefi_installs () {
        if (!Config.UEFI_INSTALLS_SUPPORTED)
            return false;

        try {
            var domain_capabilities =
                default_connection.get_domain_capabilities (null, null, null, null, 0);
            foreach (var firmware in domain_capabilities.get_os ().get_firmwares ()) {
                if (firmware == GVirConfig.DomainOsFirmware.EFI)
                    return true;
            }
        } catch (GLib.Error error) {
            warning ("Failed to obtain domain capabilities: %s", error.message);
        }

        return false;
    }
}
