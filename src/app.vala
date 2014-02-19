// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;
using Clutter;

private abstract class Boxes.Broker : GLib.Object {
    // Overriding subclass should chain-up at the end of its implementation
    public virtual async void add_source (CollectionSource source) {
        var used_configs = new GLib.List<BoxConfig> ();
        foreach (var item in App.app.collection.items.data) {
            if (!(item is Machine))
                continue;

            used_configs.append ((item as Machine).config);
        }

        source.purge_stale_box_configs (used_configs);
    }
}

private enum Boxes.AppPage {
    MAIN,
    DISPLAY
}

// Ideally Boxes.App should inherit from, Gtk.Application, but we can't also inherit from Boxes.UI,
// so we make it a separate object that calls into Boxes.App
private class Boxes.Application: Gtk.Application {
    public Application () {
        application_id = "org.gnome.Boxes";
        flags |= ApplicationFlags.HANDLES_COMMAND_LINE;
    }

    public override void startup () {
        base.startup ();
        App.app.startup ();
    }

    public override void activate () {
        base.activate ();
        App.app.activate ();
    }

    public override int command_line (GLib.ApplicationCommandLine cmdline) {
        return App.app.command_line (cmdline);
    }
}

private class Boxes.App: GLib.Object, Boxes.UI {
    public static App app;
    public Clutter.Actor actor { get { return stage; } }
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }
    public Gtk.ApplicationWindow window;
    [CCode (notify = false)]
    public bool fullscreen {
        get { return WindowState.FULLSCREEN in window.get_window ().get_state (); }
        set {
            if (value)
                window.fullscreen ();
            else
                window.unfullscreen ();
        }
    }
    public AppPage page {
        get {
            if (stack.get_visible_child_name () == "display-page")
                return AppPage.DISPLAY;
            else
                return AppPage.MAIN;
        }
        set {
            if (value == AppPage.DISPLAY) {
                stack.transition_type = Gtk.StackTransitionType.SLIDE_RIGHT;
                stack.set_visible_child_name ("display-page");
            } else {
                stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT;
                stack.set_visible_child_name ("main-page");
            }
        }
    }

    private bool maximized { get { return WindowState.MAXIMIZED in window.get_window ().get_state (); } }
    private Gtk.Stack stack;
    public ClutterWidget embed;
    public Clutter.Stage stage;
    public Clutter.BinLayout stage_bin;
    public CollectionItem current_item; // current object/vm manipulated
    public Searchbar searchbar;
    public Topbar topbar;
    public Notificationbar notificationbar;
    public Sidebar sidebar;
    public Selectionbar selectionbar;
    public uint duration;
    public GLib.Settings settings;
    public Wizard wizard;
    public Properties properties;
    public DisplayPage display_page;
    public EmptyBoxes empty_boxes;
    public string? uri { get; set; }
    public Collection collection;
    public CollectionFilter filter;
    private Gtk.Stack content_bin;
    private Clutter.Actor content_bin_actor;

    private bool is_ready;
    public signal void ready ();
    public signal void item_selected (CollectionItem item);
    private Boxes.Application application;
    public CollectionView view;

    private HashTable<string,Broker> brokers;
    private HashTable<string,CollectionSource> sources;
    public GVir.Connection default_connection { owned get { return LibvirtBroker.get_default ().get_connection ("QEMU Session"); } }
    public CollectionSource default_source { get { return sources.get ("QEMU Session"); } }

    private uint configure_id;
    private GLib.Binding status_bind;
    private ulong got_error_id;
    public static const uint configure_id_timeout = 100;  // 100ms

    public App () {
        app = this;
        application = new Boxes.Application ();
        settings = new GLib.Settings ("org.gnome.boxes");
        sources = new HashTable<string,CollectionSource> (str_hash, str_equal);
        brokers = new HashTable<string,Broker> (str_hash, str_equal);
        filter = new Boxes.CollectionFilter ();
        var action = new GLib.SimpleAction ("quit", null);
        action.activate.connect (() => { quit (); });
        application.add_action (action);

        action = new GLib.SimpleAction ("new", null);
        action.activate.connect (() => { set_state (UIState.WIZARD); });
        application.add_action (action);

        action = new GLib.SimpleAction ("select-all", null);
        action.activate.connect (() => { view.select (SelectionCriteria.ALL); });
        application.add_action (action);

        action = new GLib.SimpleAction ("select-running", null);
        action.activate.connect (() => { view.select (SelectionCriteria.RUNNING); });
        application.add_action (action);

        action = new GLib.SimpleAction ("select-none", null);
        action.activate.connect (() => { view.select (SelectionCriteria.NONE); });
        application.add_action (action);

        action = new GLib.SimpleAction ("help", null);
        action.activate.connect (() => {
            try {
                Gtk.show_uri (window.get_screen (),
                              "help:gnome-boxes",
                              Gtk.get_current_event_time ());
            } catch (GLib.Error e) {
                warning ("Failed to display help: %s", e.message);
            }
        });
        application.add_action (action);

        action = new GLib.SimpleAction ("about", null);
        action.activate.connect (() => {
            string[] authors = {
                "Alexander Larsson <alexl@redhat.com>",
                "Christophe Fergeau <cfergeau@redhat.com>",
                "Marc-André Lureau <marcandre.lureau@gmail.com>",
                "Zeeshan Ali (Khattak) <zeeshanak@gnome.org>"
            };
            string[] artists = {
                "Jon McCann <jmccann@redhat.com>",
                "Jakub Steiner <jsteiner@redhat.com>"
            };

            Gtk.show_about_dialog (window,
                                   "artists", artists,
                                   "authors", authors,
                                   "translator-credits", _("translator-credits"),
                                   "comments", _("A simple GNOME 3 application to access remote or virtual systems"),
                                   "copyright", "Copyright 2011 Red Hat, Inc.",
                                   "license-type", Gtk.License.LGPL_2_1,
                                   "logo-icon-name", "gnome-boxes",
                                   "version", Config.VERSION,
                                   "website", "http://live.gnome.org/Boxes",
                                   "wrap-license", true);
        });
        application.add_action (action);

        notify["ui-state"].connect (ui_state_changed);
    }

    public void startup () {
        string [] args = {};
        unowned string [] args2 = args;
        GtkClutter.init (ref args2);

        var menu = new GLib.Menu ();
        menu.append (_("New"), "app.new");

        var display_section = new GLib.Menu ();
        menu.append_section (null, display_section);

        menu.append (_("Help"), "app.help");
        menu.append (_("About"), "app.about");
        menu.append (_("Quit"), "app.quit");

        application.set_app_menu (menu);

        collection = new Collection ();
        duration = settings.get_int ("animation-duration");

        collection.item_added.connect ((item) => {
            view.add_item (item);
        });
        collection.item_removed.connect ((item) => {
            view.remove_item (item);
        });

        brokers.insert ("libvirt", LibvirtBroker.get_default ());
        if (Config.HAVE_OVIRT)
            brokers.insert ("ovirt", OvirtBroker.get_default ());

        setup_sources.begin ((obj, result) => {
            setup_sources.end (result);
            is_ready = true;
            ready ();
        });

        check_cpu_vt_capability.begin ();
        check_module_kvm_loaded.begin ();
    }

    public bool has_broker_for_source_type (string type) {
        return brokers.contains (type);
    }

    public delegate void CallReadyFunc ();
    public void call_when_ready (owned CallReadyFunc func) {
        if (is_ready)
            func ();
        ready.connect (() => {
            func ();
        });
    }

    public void activate () {
        setup_ui ();
        window.present ();
    }

    static bool opt_fullscreen;
    static bool opt_help;
    static string opt_open_uuid;
    static string[] opt_uris;
    static string[] opt_search;
    static const OptionEntry[] options = {
        { "version", 0, 0, OptionArg.NONE, null, N_("Display version number"), null },
        { "help", 'h', OptionFlags.HIDDEN, OptionArg.NONE, ref opt_help, null, null },
        { "full-screen", 'f', 0, OptionArg.NONE, ref opt_fullscreen, N_("Open in full screen"), null },
        { "checks", 0, 0, OptionArg.NONE, null, N_("Check virtualization capabilities"), null },
        { "open-uuid", 0, 0, OptionArg.STRING, ref opt_open_uuid, N_("Open box with UUID"), null },
        { "search", 0, 0, OptionArg.STRING_ARRAY, ref opt_search, N_("Search term"), null },
        // A 'broker' is a virtual-machine manager (could be local or remote). Currently libvirt is the only one supported.
        { "", 0, 0, OptionArg.STRING_ARRAY, ref opt_uris, N_("URI to display, broker or installer media"), null },
        { null }
    };

    public int command_line (GLib.ApplicationCommandLine cmdline) {
        opt_fullscreen = false;
        opt_help = false;
        opt_open_uuid = null;
        opt_uris = null;
        opt_search = null;

        var parameter_string = _("- A simple application to access remote or virtual machines");
        var opt_context = new OptionContext (parameter_string);
        opt_context.add_main_entries (options, null);
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

        application.activate ();

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
                var is_uri = (Uri.parse_scheme (arg) != null);

                if (file.query_exists ()) {
                    if (is_uri)
                        wizard.open_with_uri (file.get_uri ());
                    else
                        wizard.open_with_uri (arg);
                } else if (is_uri)
                    wizard.open_with_uri (file.get_uri ());
                else
                    open (arg);
            });
        }

        if (opt_search != null) {
            call_when_ready (() => {
                searchbar.text = string.joinv (" ", opt_search);
                if (ui_state == UIState.COLLECTION)
                    searchbar.visible = true;
            });
        }

        if (opt_fullscreen)
            app.fullscreen = true;

        return 0;
    }

    public int run (string [] args) {
        return application.run (args);
    }

    // To be called to tell App to release the resources it's handling.
    // Currently this only releases the GtkApplication we use, but
    // more shutdown work could be done here in the future
    public void shutdown () {
        application = null;
    }

    public void open (string name) {
        set_state (UIState.COLLECTION);
        // we don't want to show the collection items as it will
        // appear as a glitch when opening a box immediately
        view.visible = false;

        // after "ready" all items should be listed
        foreach (var item in collection.items.data) {
            if (item.name == name) {
                select_item (item);

                break;
            }
        }
    }

    public bool open_uuid (string uuid) {
        set_state (UIState.COLLECTION);
        // we don't want to show the collection items as it will
        // appear as a glitch when opening a box immediately
        view.visible = false;

        // after "ready" all items should be listed
        foreach (var item in collection.items.data) {
            if (!(item is Boxes.Machine))
                continue;
            var machine = item as Boxes.Machine;

            if (machine.config.uuid != uuid)
                continue;

            select_item (item);
            return true;
        }

        return false;
    }

    public void delete_machine (Machine machine, bool by_user = true) {
        machine.delete (by_user);         // Will also delete associated storage volume if by_user is 'true'
        collection.remove_item (machine);
    }

    public async void add_collection_source (CollectionSource source) {
        if (!source.enabled)
            return;

        if (sources.get (source.name) != null) {
            warning ("Attempt to add duplicate collection source '%s', ignoring..", source.name);
            return; // Already added
        }

        switch (source.source_type) {
        case "vnc":
        case "spice":
            try {
                var machine = new RemoteMachine (source);
                collection.add_item (machine);
            } catch (Boxes.Error error) {
                warning (error.message);
            }
            break;

        default:
            Broker? broker = brokers.lookup (source.source_type);
            if (broker != null) {
                yield broker.add_source (source);
                sources.insert (source.name, source);
                if (source.name == "QEMU Session") {
                    notify_property ("default-connection");
                    notify_property ("default-source");
                }
            } else {
                warning ("Unsupported source type %s", source.source_type);
            }
            break;
        }
    }

    private async void setup_sources () {

        if (!FileUtils.test (get_user_pkgconfig_source ("QEMU Session"), FileTest.IS_REGULAR)) {
            var src = File.new_for_path (get_pkgdata_source ("QEMU_Session"));
            var dst = File.new_for_path (get_user_pkgconfig_source ("QEMU Session"));
            try {
                yield src.copy_async (dst, FileCopyFlags.NONE);
            } catch (GLib.Error error) {
                critical ("Can't setup default sources: %s", error.message);
            }
        }

        var dir = File.new_for_path (get_user_pkgconfig_source ());
        var new_sources = new GLib.List<CollectionSource> ();
        yield foreach_filename_from_dir (dir, (filename) => {
            var source = new CollectionSource.with_file (filename);
            new_sources.append (source);
            return false;
        });

        foreach (var source in new_sources)
            yield add_collection_source (source);

        if (default_connection == null) {
            printerr ("Missing or failing default libvirt connection\n");
            application.release (); // will end application
        }
    }

    private void save_window_geometry () {
        int width, height, x, y;

        if (maximized)
            return;

        window.get_size (out width, out height);
        settings.set_value ("window-size", new int[] { width, height });

        window.get_position (out x, out y);
        settings.set_value ("window-position", new int[] { x, y });
    }

    private bool ui_is_setup;
    private void setup_ui () {
        if (ui_is_setup)
            return;
        ui_is_setup = true;
        Gtk.Window.set_default_icon_name ("gnome-boxes");
        Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;

        var provider = Boxes.load_css ("gtk-style.css");
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (),
                                                  provider,
                                                  600);

        window = new Gtk.ApplicationWindow (application);
        window.show_menubar = false;

        // restore window geometry/position
        var size = settings.get_value ("window-size");
        if (size.n_children () == 2) {
            var width = (int) size.get_child_value (0);
            var height = (int) size.get_child_value (1);

            window.set_default_size (width, height);
        }

        if (settings.get_boolean ("window-maximized"))
            window.maximize ();

        var position = settings.get_value ("window-position");
        if (position.n_children () == 2) {
            var x = (int) position.get_child_value (0);
            var y = (int) position.get_child_value (1);

            window.move (x, y);
        }

        window.configure_event.connect (() => {
            if (fullscreen)
                return false;

            if (configure_id != 0)
                GLib.Source.remove (configure_id);
            configure_id = Timeout.add (configure_id_timeout, () => {
                configure_id = 0;
                save_window_geometry ();

                return false;
            });

            return false;
        });
        window.window_state_event.connect ((event) => {
            if (WindowState.FULLSCREEN in event.changed_mask)
                this.notify_property ("fullscreen");

            if (fullscreen)
                return false;

            settings.set_boolean ("window-maximized", maximized);
            return false;
        });

        var main_vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        window.add (main_vbox);

        stack = new Gtk.Stack ();
        main_vbox.add (stack);

        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        vbox.halign = Gtk.Align.FILL;
        vbox.valign = Gtk.Align.FILL;
        vbox.hexpand = true;
        vbox.vexpand = true;
        stack.add_named (vbox, "main-page");

        searchbar = new Searchbar ();
        vbox.add (searchbar);

        embed = new ClutterWidget ();
        vbox.add (embed);

        display_page = new DisplayPage ();
        stack.add_named (display_page, "display-page");

        selectionbar = new Selectionbar ();
        main_vbox.add (selectionbar);

        stage = embed.get_stage () as Clutter.Stage;
        stage.set_background_color (gdk_rgba_to_clutter_color (get_boxes_bg_color ()));

        window.delete_event.connect (() => { return quit (); });

        window.key_press_event.connect_after (on_key_pressed);

        stage_bin = new Clutter.BinLayout (Clutter.BinAlignment.START,
                                           Clutter.BinAlignment.START);
        stage.set_layout_manager (stage_bin);
        stage.name = "boxes-stage";

        var background = new GtkClutter.Texture ();
        background.name = "background";
        try {
            var pixbuf = load_asset ("boxes-dark.png");
            background.set_from_pixbuf (pixbuf);
        } catch (GLib.Error e) {
            warning ("Failed to load asset 'boxes-dark.png': %s", e.message);
        }
        background.set_repeat (true, true);
        background.x_align = Clutter.ActorAlign.FILL;
        background.y_align = Clutter.ActorAlign.FILL;
        background.x_expand = true;
        background.y_expand = true;
        stage.add_child (background);

        sidebar = new Sidebar ();
        view = new CollectionView ();
        topbar = new Topbar ();
        notificationbar = new Notificationbar ();
        wizard = new Wizard ();
        properties = new Properties ();
        empty_boxes = new EmptyBoxes ();

        window.set_titlebar (topbar);

        var below_bin_actor = new Clutter.Actor ();
        below_bin_actor.name = "below-bin";
        var below_bin = new Clutter.BinLayout (Clutter.BinAlignment.START,
                                               Clutter.BinAlignment.START);
        below_bin_actor.set_layout_manager (below_bin);

        below_bin_actor.x_expand = true;
        below_bin_actor.y_expand = true;
        stage.add_child (below_bin_actor);

        below_bin_actor.add_child (view.actor);

        var hbox_actor = new Clutter.Actor ();
        hbox_actor.name = "top-hbox";
        var hbox = new Clutter.BoxLayout ();
        hbox_actor.set_layout_manager (hbox);
        hbox_actor.x_align = Clutter.ActorAlign.FILL;
        hbox_actor.y_align = Clutter.ActorAlign.FILL;
        hbox_actor.x_expand = true;
        hbox_actor.y_expand = true;

        below_bin_actor.add_child (hbox_actor);

        hbox_actor.add_child (sidebar.actor);

        content_bin = new Gtk.Stack ();
        content_bin.vexpand = true;
        content_bin.hexpand = true;
        content_bin.add (wizard);
        content_bin.add (properties);
        content_bin_actor  = new GtkClutter.Actor.with_contents (content_bin);
        content_bin_actor.x_align = Clutter.ActorAlign.FILL;
        content_bin_actor.y_align = Clutter.ActorAlign.FILL;
        content_bin_actor.x_expand = true;
        content_bin_actor.y_expand = true;
        hbox_actor.add_child (content_bin_actor);

        below_bin_actor.add_child (notificationbar.actor);

        below_bin_actor.insert_child_below (empty_boxes.actor, notificationbar.actor);

        properties.actor.hide ();

        main_vbox.show_all ();

        set_state (UIState.COLLECTION);
    }

    private void set_main_ui_state () {
        stack.set_visible_child_name ("main-page");
    }

    private void ui_state_changed () {
        // The order is important for some widgets here (e.g properties must change its state before wizard so it can
        // flush any deferred changes for wizard to pick-up when going back from properties to wizard (review).
        foreach (var ui in new Boxes.UI[] { sidebar, topbar, view, properties, wizard, empty_boxes }) {
            ui.set_state (ui_state);
        }

        if (ui_state != UIState.DISPLAY)
            set_main_ui_state ();

        if (ui_state != UIState.COLLECTION)
            searchbar.visible = false;

        content_bin_actor.visible = (ui_state == UIState.WIZARD || ui_state == UIState.PROPERTIES);

        switch (ui_state) {
        case UIState.COLLECTION:
            topbar.status = null;
            status_bind = null;
            if (current_item is Machine) {
                var machine = current_item as Machine;
                if (got_error_id != 0) {
                    machine.disconnect (got_error_id);
                    got_error_id = 0;
                }

                machine.connecting_cancellable.cancel (); // Cancel any in-progress connections
            }
            fullscreen = false;
            view.visible = true;

            break;

        case UIState.CREDS:

            break;

        case UIState.WIZARD:
            content_bin.visible_child = wizard;

            break;

        case UIState.PROPERTIES:
            content_bin.visible_child = properties;

            break;

        case UIState.DISPLAY:
            if (maximized)
                fullscreen = true;

            break;

        default:
            warning ("Unhandled UI state %s".printf (ui_state.to_string ()));
            break;
        }

        if (current_item != null)
            current_item.set_state (ui_state);
    }

    public void suspend_machines () {
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
        foreach (var item in collection.items.data) {
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
        }
        context.pop_thread_default ();

        // wait for async methods to complete
        while (waiting_counter > 0)
            context.iteration (true);

        debug ("Running boxes suspended");
    }

    public bool quit () {
        notificationbar.cancel ();
        save_window_geometry ();
        wizard.cleanup ();
        window.destroy ();

        return false;
    }

    private bool _selection_mode;
    public bool selection_mode { get { return _selection_mode; }
        set {
            return_if_fail (ui_state == UIState.COLLECTION);

            _selection_mode = value;
        }
    }

    public List<CollectionItem> selected_items {
        owned get { return view.get_selected_items (); }
    }

    public void show_properties () {
        var selected_items = view.get_selected_items ();

        selection_mode = false;

        // Show for the first selected item
        foreach (var item in selected_items) {
            current_item = item;
            set_state (UIState.PROPERTIES);
            break;
        }
    }

    public void remove_selected_items () {
        var selected_items = view.get_selected_items ();
        var num_selected = selected_items.length ();
        if (num_selected == 0)
            return;

        selection_mode = false;

        var message = (num_selected == 1) ? _("Box '%s' has been deleted").printf (selected_items.data.name) :
                                            ngettext ("%u box has been deleted",
                                                      "%u boxes have been deleted",
                                                      num_selected).printf (num_selected);
        foreach (var item in selected_items)
            collection.remove_item (item);

        Notification.OKFunc undo = () => {
            debug ("Box deletion cancelled by user, re-adding to view");
            foreach (var selected in selected_items) {
                collection.add_item (selected);
            }
        };

        Notification.CancelFunc really_remove = () => {
            debug ("Box deletion, deleting now");
            foreach (var selected in selected_items) {
                var machine = selected as Machine;

                if (machine != null)
                    machine.delete ();
            }
        };

        notificationbar.display_for_action (message, _("_Undo"), (owned) undo, (owned) really_remove);
    }

    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        var default_modifiers = Gtk.accelerator_get_default_mod_mask ();

        if (event.keyval == Gdk.Key.F11) {
            fullscreen = !fullscreen;
            return true;
        } else if (event.keyval == Gdk.Key.Escape) {
            if (selection_mode && ui_state == UIState.COLLECTION)
               selection_mode = false;
        } else if (event.keyval == Gdk.Key.q &&
                   (event.state & default_modifiers) == Gdk.ModifierType.CONTROL_MASK) {
            quit ();
            return true;
        } else if (event.keyval == Gdk.Key.a &&
                   (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            quit ();
            return true;
        }

        return false;
    }

    public void connect_to (Machine machine) {
        current_item = machine;

        // Track machine status in toobar
        status_bind = machine.bind_property ("status", topbar, "status", BindingFlags.SYNC_CREATE);

        got_error_id = machine.got_error.connect ( (message) => {
            App.app.notificationbar.display_error (message);
        });

        if (ui_state != UIState.CREDS)
            set_state (UIState.CREDS); // Start the CREDS state
    }

    public void select_item (CollectionItem item) {
        if (ui_state == UIState.COLLECTION && !selection_mode) {
            current_item = item;

            if (current_item is Machine) {
                var machine = current_item as Machine;

                connect_to (machine);
            } else
                warning ("unknown item, fix your code");

            item_selected (item);
        } else if (ui_state == UIState.WIZARD) {
            current_item = item;

            set_state (UIState.PROPERTIES);
        }
    }
}
