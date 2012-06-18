// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;
using Clutter;

private enum Boxes.AppPage {
    MAIN,
    DISPLAY
}

private class Boxes.App: Boxes.UI {
    public static App app;
    public override Clutter.Actor actor { get { return stage; } }
    public Gtk.ApplicationWindow window;
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
    public GtkClutter.Embed embed;
    public Clutter.Stage stage;
    public Clutter.BinLayout stage_bin;
    public Clutter.Actor overlay_bin_actor;
    public Clutter.BinLayout overlay_bin;
    public CollectionItem current_item; // current object/vm manipulated
    public Topbar topbar;
    public Notificationbar notificationbar;
    public Boxes.Revealer sidebar_revealer;
    public Boxes.Revealer topbar_revealer;
    public Sidebar sidebar;
    public Selectionbar selectionbar;
    public uint duration;
    public GLib.Settings settings;
    public Wizard wizard;
    public Properties properties;
    public DisplayPage display_page;
    public string? uri { get; set; }
    public Collection collection;
    public GLib.SimpleAction action_properties;
    public GLib.SimpleAction action_fullscreen;
    public GLib.SimpleAction action_shutdown;

    public signal void ready (bool first_time);
    public signal void item_selected (CollectionItem item);
    private Gtk.Application application;
    private CollectionView view;

    private HashTable<string,GVir.Connection> connections;
    private HashTable<string,CollectionSource> sources;
    public GVir.Connection default_connection { get { return connections.get ("QEMU Session"); } }
    public CollectionSource default_source { get { return sources.get ("QEMU Session"); } }

    private uint configure_id;
    public static const uint configure_id_timeout = 100;  // 100ms

    public App () {
        app = this;
        application = new Gtk.Application ("org.gnome.Boxes", 0);
        settings = new GLib.Settings ("org.gnome.boxes");
        connections = new HashTable<string, GVir.Connection> (str_hash, str_equal);
        sources = new HashTable<string,CollectionSource> (str_hash, str_equal);

        var action = new GLib.SimpleAction ("quit", null);
        action.activate.connect (() => { quit (); });
        application.add_action (action);

        action = new GLib.SimpleAction ("new", null);
        action.activate.connect (() => { ui_state = UIState.WIZARD; });
        application.add_action (action);

        action_fullscreen = new GLib.SimpleAction ("display.fullscreen", null);
        action_fullscreen.activate.connect (() => { fullscreen = true; });
        application.add_action (action_fullscreen);

        action_properties = new GLib.SimpleAction ("display.properties", null);
        action_properties.activate.connect (() => { ui_state = UIState.PROPERTIES; });
        application.add_action (action_properties);

        action_shutdown = new GLib.SimpleAction ("display.shutdown", null);
        action_shutdown.activate.connect (() => { (current_item as LibvirtMachine).force_shutdown (); });
        application.add_action (action_shutdown);

        action = new GLib.SimpleAction ("about", null);
        action.activate.connect (() => {
            string[] authors = {
                "Zeeshan Ali (Khattak) <zeeshanak@gnome.org>",
                "Marc-André Lureau <marcandre.lureau@gmail.com>"
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

        application.startup.connect_after ((app) => {
            var menu = new GLib.Menu ();
            menu.append (_("New"), "app.new");

            var display_section = new GLib.Menu ();
            display_section.append (_("Properties"), "app.display.properties");
            display_section.append (_("Fullscreen"), "app.display.fullscreen");
            display_section.append (_("Force shutdown"), "app.display.shutdown");
            menu.append_section (null, display_section);

            menu.append (_("About Boxes"), "app.about");
            menu.append (_("Quit"), "app.quit");

            application.set_app_menu (menu);

            collection = new Collection ();
            duration = settings.get_int ("animation-duration");
            setup_ui ();

            collection.item_added.connect ((item) => {
                view.add_item (item);
            });
            collection.item_removed.connect ((item) => {
                view.remove_item (item);
            });
            setup_sources.begin ((obj, result) => {
                setup_sources.end (result);
                var no_items = collection.items.length == 0;
                ready (no_items);
            });

            check_cpu_vt_capability ();
            check_module_kvm_loaded ();
        });

        application.activate.connect_after ((app) => {
            window.present ();
        });
    }

    public int run () {
        return application.run ();
    }

    public bool open (string name) {
        ui_state = UIState.COLLECTION;
        view.visible = false; // to avoid some glitches

        // after "ready" all items should be listed
        foreach (var item in collection.items.data) {
            if (item.name != name)
                continue;

            return select_item (item);
        }

        return false;
    }

    public LibvirtMachine? add_domain (CollectionSource source, GVir.Connection connection, GVir.Domain domain) {
        var machine = domain.get_data<LibvirtMachine> ("machine");
        if (machine != null)
            return machine; // Already added

        try {
            machine = new LibvirtMachine (source, connection, domain);
            collection.add_item (machine);
            domain.set_data<LibvirtMachine> ("machine", machine);
        } catch (GLib.Error error) {
            warning ("Failed to create source '%s': %s", source.name, error.message);
        }

        return machine;
    }

    private async void setup_libvirt (CollectionSource source) {
        if (connections.lookup (source.name) != null)
            return;

        var connection = new GVir.Connection (source.uri);

        try {
            yield connection.open_async (null);
            yield connection.fetch_domains_async (null);
            yield connection.fetch_storage_pools_async (null);
            var pool = connection.find_storage_pool_by_name (Config.PACKAGE_TARNAME);
            if (pool != null)
                // If default storage pool exists, we should refresh it already
                yield pool.refresh_async (null);
        } catch (GLib.Error error) {
            warning (error.message);
        }

        connections.insert (source.name, connection);
        sources.insert (source.name, source);
        if (source.name == "QEMU Session") {
            notify_property ("default-connection");
            notify_property ("default-source");
        }

        foreach (var domain in connection.get_domains ())
            add_domain (source, connection, domain);

        connection.domain_removed.connect ((connection, domain) => {
            var machine = domain.get_data<LibvirtMachine> ("machine");
            if (machine == null)
                return; // Looks like we removed the domain ourselves. Nothing to do then..

            machine.delete (false);
            collection.remove_item (machine);
        });

        connection.domain_added.connect ((connection, domain) => {
            debug ("New domain '%s'", domain.get_name ());
            add_domain (source, connection, domain);
        });
    }

    public async void add_collection_source (CollectionSource source) {
        if (!source.enabled)
            return;

        switch (source.source_type) {
        case "libvirt":
            yield setup_libvirt (source);
            break;

        case "vnc":
        case "spice":
            var machine = new RemoteMachine (source);
            collection.add_item (machine);
            break;

        default:
            warning ("Unsupported source type %s", source.source_type);
            break;
        }
    }

    private async void setup_sources () {

        if (!has_user_pkgconfig_sources ()) {
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
            printerr ("error: missing or failing default libvirt connection");
            application.release (); // will end application
        }

        var dir = File.new_for_path (get_user_pkgconfig_source ());
        yield get_sources_from_dir (dir);
    }

    private async void get_sources_from_dir (File dir) {
        try {
            var enumerator = yield dir.enumerate_children_async (FILE_ATTRIBUTE_STANDARD_NAME, 0);
            while (true) {
                var files = yield enumerator.next_files_async (10);
                if (files == null)
                    break;

                foreach (var file in files) {
                    var source = new CollectionSource.with_file (file.get_name ());
                    add_collection_source (source);
                }
            }
        } catch (GLib.Error error) {
            warning (error.message);
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

    private void setup_ui () {
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
        window.window_state_event.connect (() => {
            if (fullscreen)
                return false;

            settings.set_boolean ("window-maximized", maximized);
            return false;
        });

        notebook = new Gtk.Notebook ();
        notebook.show_border = false;
        notebook.show_tabs = false;
        window.add (notebook);
        embed = new GtkClutter.Embed ();
        notebook.append_page (embed, null);

        display_page = new DisplayPage ();
        notebook.append_page (display_page.widget, null);

        stage = embed.get_stage () as Clutter.Stage;
        stage.set_background_color (gdk_rgba_to_clutter_color (get_boxes_bg_color ()));

        window.delete_event.connect (() => { return quit (); });

        window.key_press_event.connect (on_key_pressed);

        stage_bin = new Clutter.BinLayout (Clutter.BinAlignment.FIXED,
                                           Clutter.BinAlignment.FIXED);
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
        stage_bin.add (background,
                       Clutter.BinAlignment.FILL,
                       Clutter.BinAlignment.FILL);

        sidebar = new Sidebar ();
        view = new CollectionView ();
        topbar = new Topbar ();
        notificationbar = new Notificationbar ();
        selectionbar = new Selectionbar ();
        wizard = new Wizard ();
        properties = new Properties ();

        var vbox_actor = new Clutter.Actor ();
        vbox_actor.name = "top-vbox";
        var vbox = new Clutter.BoxLayout ();
        vbox_actor.set_layout_manager (vbox);
        vbox.set_vertical (true);

        stage_bin.add (vbox_actor,
                       Clutter.BinAlignment.FILL,
                       Clutter.BinAlignment.FILL);

        topbar_revealer = new Boxes.Revealer (true);
        topbar_revealer.name = "topbar-revealer";
        vbox.pack (topbar_revealer, false, true, true, Clutter.BoxAlignment.START, Clutter.BoxAlignment.START);
        topbar_revealer.add (topbar.actor);

        var below_bin_actor = new Clutter.Actor ();
        below_bin_actor.name = "below-bin";
        var below_bin = new Clutter.BinLayout (Clutter.BinAlignment.FIXED,
                                               Clutter.BinAlignment.FIXED);
        below_bin_actor.set_layout_manager (below_bin);

        vbox.pack (below_bin_actor, true, true, true, Clutter.BoxAlignment.START, Clutter.BoxAlignment.START);

        below_bin.add (view.actor,
                       Clutter.BinAlignment.FILL,
                       Clutter.BinAlignment.FILL);

        var hbox_actor = new Clutter.Actor ();
        hbox_actor.name = "top-hbox";
        var hbox = new Clutter.BoxLayout ();
        hbox_actor.set_layout_manager (hbox);

        below_bin.add (hbox_actor,
                       Clutter.BinAlignment.FILL,
                       Clutter.BinAlignment.FILL);

        overlay_bin_actor = new Clutter.Actor ();
        overlay_bin_actor.name = "overlay-bin";
        overlay_bin = new Clutter.BinLayout (Clutter.BinAlignment.FIXED,
                                             Clutter.BinAlignment.FIXED);
        overlay_bin_actor.set_layout_manager (overlay_bin);
        overlay_bin.set ("use-animations", true,
                         "easing-mode", Clutter.AnimationMode.LINEAR,
                         "easing-duration", duration);
        below_bin.add (overlay_bin_actor,
                       Clutter.BinAlignment.FILL,
                       Clutter.BinAlignment.FILL);

        sidebar_revealer = new Boxes.Revealer (false);
        sidebar_revealer.name = "sidebar-revealer";
        hbox.pack (sidebar_revealer, false, true, true, Clutter.BoxAlignment.START, Clutter.BoxAlignment.START);
        sidebar_revealer.unreveal ();
        sidebar_revealer.add (sidebar.actor);

        var content_bin_actor = new Clutter.Actor ();
        content_bin_actor.name = "content-bin";
        var content_bin = new Clutter.BinLayout (Clutter.BinAlignment.FILL,
                                                 Clutter.BinAlignment.FILL);
        content_bin_actor.set_layout_manager (content_bin);
        hbox.pack (content_bin_actor, true, true, true, Clutter.BoxAlignment.START, Clutter.BoxAlignment.START);

        below_bin.add (notificationbar.actor, Clutter.BinAlignment.CENTER, Clutter.BinAlignment.START);

        content_bin.add (selectionbar.actor, Clutter.BinAlignment.CENTER, Clutter.BinAlignment.END);
        content_bin_actor.add (wizard.actor);
        content_bin_actor.add (properties.actor);

        properties.actor.hide ();
        selectionbar.actor.hide ();

        notebook.show_all ();

        ui_state = UIState.COLLECTION;
    }

    private void set_main_ui_state () {
        notebook.page = Boxes.AppPage.MAIN;
    }

    public override void ui_state_changed () {
        action_fullscreen.set_enabled (ui_state == UIState.DISPLAY);
        action_properties.set_enabled (ui_state == UIState.DISPLAY);
        action_shutdown.set_enabled (ui_state == UIState.DISPLAY && current_item is LibvirtMachine);

        foreach (var ui in new Boxes.UI[] { sidebar, topbar, view, wizard, properties }) {
            ui.ui_state = ui_state;
        }

        switch (ui_state) {
        case UIState.COLLECTION:
            set_main_ui_state ();
            if (current_item is Machine) {
                var machine = current_item as Machine;

                machine.disconnect_display ();
                machine.update_screenshot.begin ();
            }
            fullscreen = false;
            view.visible = true;
            break;

        case UIState.CREDS:
        case UIState.PROPERTIES:
        case UIState.WIZARD:
            set_main_ui_state ();
            break;

        case UIState.DISPLAY:
            break;

        default:
            warning ("Unhandled UI state %s".printf (ui_state.to_string ()));
            break;
        }
    }

    public bool quit () {
        notificationbar.cancel ();
        save_window_geometry ();
        window.destroy ();

        foreach (var item in collection.items.data)
            if (item is LibvirtMachine) {
                var machine = item as LibvirtMachine;

                if (machine.connection == default_connection)
                    machine.suspend.begin ();
            }

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
            view.remove_item (item);

        Notificationbar.OKFunc undo = () => {
            debug ("Box deletion cancelled by user, re-adding to view");
            foreach (var selected in selected_items) {
                view.add_item (selected);
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
    }

    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        if (event.keyval == Gdk.Key.F11) {
            fullscreen = !fullscreen;
            return true;
        } else if (event.keyval == Gdk.Key.Escape) {
            if (selection_mode && ui_state == UIState.COLLECTION)
               selection_mode = false;
        }

        return false;
    }

    public bool select_item (CollectionItem item) {
        if (ui_state == UIState.COLLECTION && !selection_mode) {
            current_item = item;

            if (current_item is Machine) {
                var machine = current_item as Machine;

                machine.connect_display ();
                ui_state = UIState.CREDS;
            } else
                warning ("unknown item, fix your code");

            item_selected (item);
        }

        return false;
    }
}
