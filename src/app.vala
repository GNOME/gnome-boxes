// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;
using Clutter;

private abstract class Boxes.Broker : GLib.Object {
    public abstract async void add_source (CollectionSource source);
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

private class Boxes.App: Boxes.UI {
    public static App app;
    public override Clutter.Actor actor { get { return stage; } }
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

    private bool maximized { get { return WindowState.MAXIMIZED in window.get_window ().get_state (); } }
    public Gtk.Notebook notebook;
    public ClutterWidget embed;
    public Clutter.Stage stage;
    public Clutter.BinLayout stage_bin;
    public Clutter.Actor overlay_bin_actor;
    public Clutter.BinLayout overlay_bin;
    public CollectionItem current_item; // current object/vm manipulated
    public Searchbar searchbar;
    public Topbar topbar;
    public Notificationbar notificationbar;
    public Boxes.Revealer sidebar_revealer;
    public Boxes.Revealer searchbar_revealer;
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
        action.activate.connect (() => { ui_state = UIState.WIZARD; });
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
                                   "version", Config.BUILD_VERSION,
                                   "website", "http://live.gnome.org/Boxes",
                                   "wrap-license", true);
        });
        application.add_action (action);
    }

    public void startup () {
        string [] args = {};
        unowned string [] args2 = args;
        GtkClutter.init (ref args2);

        var menu = new GLib.Menu ();
        menu.append (_("New"), "app.new");

        var display_section = new GLib.Menu ();
        menu.append_section (null, display_section);

        menu.append (_("About Boxes"), "app.about");
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
            var file = File.new_for_commandline_arg (arg);

            if (file.query_exists () || Uri.parse_scheme (arg) != null) {
                call_when_ready (() => {
                    wizard.open_with_uri (file.get_uri ());
                });
            } else {
                call_when_ready (() => {
                    open (arg);
                });
            }
        }

        if (opt_search != null) {
            call_when_ready (() => {
                searchbar.text = string.joinv (" ", opt_search);
                searchbar.visible = true;
                if (ui_state == UIState.COLLECTION) {
                    searchbar_revealer.revealed = true;
                }
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
        ui_state = UIState.COLLECTION;
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
        ui_state = UIState.COLLECTION;
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
            Broker? broker = brokers.lookup(source.source_type);
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

        try {
            var source = new CollectionSource.with_file ("QEMU Session");
            yield add_collection_source (source);
        } catch (GLib.Error error) {
            warning (error.message);
        }
        if (default_connection == null) {
            printerr ("Missing or failing default libvirt connection\n");
            application.release (); // will end application
        }

        var dir = File.new_for_path (get_user_pkgconfig_source ());
        yield foreach_filename_from_dir (dir, (filename) => {
            var source = new CollectionSource.with_file (filename);
            add_collection_source.begin (source);
            return false;
        });
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

        var provider = new Gtk.CssProvider ();
        try {
            var sheet = Boxes.get_style ("gtk-style.css");
            provider.load_from_path (sheet);
            Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (),
                                                      provider,
                                                      600);
        } catch (GLib.Error error) {
            warning (error.message);
        }

        window = new Gtk.ApplicationWindow (application);
        window.show_menubar = false;
        window.hide_titlebar_when_maximized = true;

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

        notebook = new Gtk.Notebook ();
        notebook.show_border = false;
        notebook.show_tabs = false;
        window.add (notebook);
        embed = new ClutterWidget ();
        notebook.append_page (embed, null);

        display_page = new DisplayPage ();
        notebook.append_page (display_page.widget, null);

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
            var pixbuf = new Gdk.Pixbuf.from_file (get_style ("assets/boxes-dark.png"));
            background.set_from_pixbuf (pixbuf);
        } catch (GLib.Error e) {
        }
        background.set_repeat (true, true);
        background.x_align = Clutter.ActorAlign.FILL;
        background.y_align = Clutter.ActorAlign.FILL;
        background.x_expand = true;
        background.y_expand = true;
        stage.add_child (background);

        sidebar = new Sidebar ();
        view = new CollectionView ();
        searchbar = new Searchbar ();
        topbar = new Topbar ();
        notificationbar = new Notificationbar ();
        selectionbar = new Selectionbar ();
        wizard = new Wizard ();
        properties = new Properties ();
        empty_boxes = new EmptyBoxes ();

        var vbox_actor = new Clutter.Actor ();
        vbox_actor.name = "top-vbox";
        var vbox = new Clutter.BoxLayout ();
        vbox_actor.set_layout_manager (vbox);
        vbox.orientation = Clutter.Orientation.VERTICAL;
        vbox_actor.x_align = Clutter.ActorAlign.FILL;
        vbox_actor.y_align = Clutter.ActorAlign.FILL;
        vbox_actor.x_expand = true;
        vbox_actor.y_expand = true;

        stage.add_child (vbox_actor);

        var topbar_revealer = new Boxes.Revealer (true);
        topbar_revealer.name = "topbar-revealer";
        topbar_revealer.x_expand = true;
        vbox_actor.add_child (topbar_revealer);
        topbar_revealer.add (topbar.actor);

        searchbar_revealer = new Boxes.Revealer (true);
        searchbar_revealer.resize = true;
        searchbar_revealer.unreveal ();
        searchbar_revealer.name = "searchbar-revealer";
        searchbar_revealer.x_expand = true;
        vbox_actor.add_child (searchbar_revealer);
        searchbar_revealer.add (searchbar.actor);

        var below_bin_actor = new Clutter.Actor ();
        below_bin_actor.name = "below-bin";
        var below_bin = new Clutter.BinLayout (Clutter.BinAlignment.START,
                                               Clutter.BinAlignment.START);
        below_bin_actor.set_layout_manager (below_bin);

        below_bin_actor.x_expand = true;
        below_bin_actor.y_expand = true;
        vbox_actor.add_child (below_bin_actor);

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

        overlay_bin_actor = new Clutter.Actor ();
        overlay_bin_actor.name = "overlay-bin";
        overlay_bin = new Clutter.BinLayout (Clutter.BinAlignment.START,
                                             Clutter.BinAlignment.START);
        overlay_bin_actor.set_layout_manager (overlay_bin);
        overlay_bin_actor.x_align = Clutter.ActorAlign.FILL;
        overlay_bin_actor.y_align = Clutter.ActorAlign.FILL;
        overlay_bin_actor.x_expand = true;
        overlay_bin_actor.y_expand = true;
        below_bin_actor.add_child (overlay_bin_actor);

        sidebar_revealer = new Boxes.Revealer (false);
        sidebar_revealer.name = "sidebar-revealer";
        sidebar_revealer.y_expand = true;
        hbox_actor.add_child (sidebar_revealer);
        sidebar_revealer.unreveal ();
        sidebar_revealer.add (sidebar.actor);

        var content_bin_actor = new Clutter.Actor ();
        content_bin_actor.name = "content-bin";
        content_bin_actor.x_align = Clutter.ActorAlign.FILL;
        content_bin_actor.y_align = Clutter.ActorAlign.FILL;
        content_bin_actor.x_expand = true;
        content_bin_actor.y_expand = true;
        var content_bin = new Clutter.BinLayout (Clutter.BinAlignment.START,
                                                 Clutter.BinAlignment.START);
        content_bin_actor.set_layout_manager (content_bin);
        hbox_actor.add_child (content_bin_actor);

        below_bin_actor.add_child (notificationbar.actor);
        below_bin_actor.add_child (selectionbar.actor);

        content_bin_actor.add (wizard.actor);
        content_bin_actor.add (properties.actor);
        below_bin_actor.insert_child_below (empty_boxes.actor, null);

        properties.actor.hide ();
        selectionbar.actor.hide ();
        empty_boxes.actor.hide ();

        notebook.show_all ();

        ui_state = UIState.COLLECTION;
    }

    private void set_main_ui_state () {
        notebook.page = Boxes.AppPage.MAIN;
    }

    private void position_item_actor_at_icon (CollectionItem item) {
        float item_x, item_y;
        view.get_item_pos (item, out item_x, out item_y);
        var actor = item.actor;
        var old_duration = actor.get_easing_duration ();
        // We temporarily set the duration to 0 because we don't want to animate
        // fixed_x/y, but rather immidiately set it to the target value and then
        // animate actor.allocation which is set based on these.
        actor.set_easing_duration (0);
        actor.fixed_x = item_x;
        actor.fixed_y = item_y;
        actor.min_width = actor.natural_width = Machine.SCREENSHOT_WIDTH;
        actor.set_easing_duration (old_duration);
    }

    public override void ui_state_changed () {
        // The order is important for some widgets here (e.g properties must change its state before wizard so it can
        // flush any deferred changes for wizard to pick-up when going back from properties to wizard (review).
        foreach (var ui in new Boxes.UI[] { sidebar, searchbar, topbar, view, properties, wizard, empty_boxes }) {
            ui.ui_state = ui_state;
        }

        if (ui_state != UIState.DISPLAY)
            set_main_ui_state ();

        if (ui_state != UIState.COLLECTION)
            searchbar_revealer.revealed = false;

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
            }
            fullscreen = false;
            view.visible = true;
            searchbar_revealer.revealed = searchbar.visible;

            // Animate current_item actor to collection position
            if (current_item != null) {
                var actor = current_item.actor;

                actor.show ();
                position_item_actor_at_icon (current_item);

                // Also track size changes in the icon_view during the animation
                var id = view.icon_view.size_allocate.connect ((allocation) => {
                    // We do this in an idle to avoid causing a layout inside a size_allocate cycle
                    Idle.add_full (Priority.HIGH, () => {
                        position_item_actor_at_icon (current_item);
                        return false;
                    });
                });
                ulong completed_id = 0;
                completed_id = actor.transitions_completed.connect (() => {
                    actor.disconnect (completed_id);
                    view.icon_view.disconnect (id);
                    if (App.app.ui_state == UIState.COLLECTION ||
                        App.app.current_item.actor != actor)
                        actor_remove (actor);
                });
            }

            break;

        case UIState.CREDS:
            break;

        case UIState.WIZARD:
            if (current_item != null)
                actor_remove (current_item.actor);
            break;

        case UIState.PROPERTIES:
            current_item.actor.hide ();
            break;

        case UIState.DISPLAY:
            break;

        default:
            warning ("Unhandled UI state %s".printf (ui_state.to_string ()));
            break;
        }

        if (current_item != null)
            current_item.ui_state = ui_state;
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
            ui_state = UIState.PROPERTIES;
            break;
        }
    }

    public void remove_selected_items () {
        var selected_items = view.get_selected_items ();
        var num_selected = selected_items.length ();
        if (num_selected == 0)
            return;

        var message = (num_selected == 1) ? _("Box '%s' has been deleted").printf (selected_items.data.name) :
                                            ngettext ("%u box has been deleted",
                                                      "%u boxes have been deleted",
                                                      num_selected).printf (num_selected);
        foreach (var item in selected_items)
            collection.remove_item (item);

        Notificationbar.OKFunc undo = () => {
            debug ("Box deletion cancelled by user, re-adding to view");
            foreach (var selected in selected_items) {
                collection.add_item (selected);
            }
        };

        Notificationbar.CancelFunc really_remove = () => {
            debug ("Box deletion, deleting now");
            foreach (var selected in selected_items) {
                var machine = selected as Machine;

                if (machine != null)
                    machine.delete ();
            }
        };

        notificationbar.display_for_action (message, Gtk.Stock.UNDO, (owned) undo, (owned) really_remove);

        // go out of selection mode if there are no more boxes
        if (App.app.collection.items.length == 0) {
            App.app.selection_mode = false;
        }
    }

    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        if (event.keyval == Gdk.Key.F11) {
            fullscreen = !fullscreen;
            return true;
        } else if (event.keyval == Gdk.Key.Escape) {
            if (selection_mode && ui_state == UIState.COLLECTION)
               selection_mode = false;
        } else if (event.keyval == Gdk.Key.q &&
                   (event.state & Gdk.ModifierType.MODIFIER_MASK) == Gdk.ModifierType.CONTROL_MASK) {
            quit ();
            return true;
        } else if (event.keyval == Gdk.Key.a &&
                   (event.state & Gdk.ModifierType.MODIFIER_MASK) == Gdk.ModifierType.MOD1_MASK) {
            quit ();
            return true;
        }

        return false;
    }

    public void connect_to (Machine machine, float x, float y) {
        current_item = machine;

        // Set up actor for CREDS animation
        var actor = machine.actor;
        if (actor.get_parent () == null) {
            App.app.overlay_bin_actor.add_child (actor);
            allocate_actor_no_animation (actor, x, y,
                                         Machine.SCREENSHOT_WIDTH,
                                         Machine.SCREENSHOT_HEIGHT * 2);
        }
        actor.show ();
        actor.set_easing_mode (Clutter.AnimationMode.LINEAR);
        actor.min_width = actor.natural_width = Machine.SCREENSHOT_WIDTH * 2;
        actor.fixed_position_set = false;
        actor.set_easing_duration (App.app.duration);

        // Track machine status in toobar
        status_bind = machine.bind_property ("status", topbar, "status", BindingFlags.SYNC_CREATE);

        got_error_id = machine.got_error.connect ( (message) => {
            App.app.notificationbar.display_error (message);
        });

        // Start the CREDS state
        ui_state = UIState.CREDS;

        // Connect to the display
        machine.connect_display.begin ( (obj, res) => {
            try {
                machine.connect_display.end (res);
            } catch (GLib.Error e) {
                ui_state = UIState.COLLECTION;
                App.app.notificationbar.display_error (_("Connection to '%s' failed").printf (machine.name));
                debug ("connect display failed: %s", e.message);
            }
            });

    }

    public void select_item (CollectionItem item) {
        if (ui_state == UIState.COLLECTION && !selection_mode) {
            current_item = item;

            if (current_item is Machine) {
                var machine = current_item as Machine;

                float item_x, item_y;
                view.get_item_pos (item, out item_x, out item_y);

                connect_to (machine, item_x, item_y);

                if (maximized)
                    fullscreen = true;
            } else
                warning ("unknown item, fix your code");

            item_selected (item);
        } else if (ui_state == UIState.WIZARD) {
            current_item = item;

            ui_state = UIState.PROPERTIES;
        }
    }
}
