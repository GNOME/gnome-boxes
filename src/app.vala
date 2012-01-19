// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;
using Clutter;

private enum Boxes.AppPage {
    MAIN,
    DISPLAY
}

private class Boxes.App: Boxes.UI {
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
    public Clutter.State state;
    public Clutter.Box box; // the whole app box
    public CollectionItem current_item; // current object/vm manipulated
    public Topbar topbar;
    public Notificationbar notificationbar;
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

    public signal void ready ();
    private Gtk.Application application;
    private Clutter.TableLayout box_table;
    private CollectionView view;

    private HashTable<string,GVir.Connection> connections;
    public GVir.Connection default_connection { get { return connections.get ("QEMU Session"); } }

    private uint configure_id;
    public static const uint configure_id_timeout = 100;  // 100ms

    public App () {
        application = new Gtk.Application ("org.gnome.Boxes", 0);
        settings = new GLib.Settings ("org.gnome.boxes");

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

        var menu = new GLib.Menu ();
        menu.append (_("New"), "app.new");

        var display_section = new GLib.Menu ();
        display_section.append (_("Properties"), "app.display.properties");
        display_section.append (_("Fullscreen"), "app.display.fullscreen");
        menu.append_section (null, display_section);

        menu.append (_("About Boxes"), "app.about");
        menu.append (_("Quit"), "app.quit");

        application.set_app_menu (menu);

        application.startup.connect_after ((app) => {
            duration = settings.get_int ("animation-duration");
            setup_ui ();
            collection = new Collection (this);
            connections = new HashTable<string, GVir.Connection> (str_hash, str_equal);
            collection.item_added.connect ((item) => {
                view.add_item (item);
            });
            collection.item_removed.connect ((item) => {
                view.remove_item (item);
            });
            setup_sources.begin ((obj, rest) => {
                ready ();
            });
        });

        application.activate.connect_after ((app) => {
            window.present ();
        });
    }

    public int run () {
        return application.run ();
    }

    public void set_category (Category category) {
        topbar.label.set_text (category.name);
        view.category = category;
    }

    private void add_domain (CollectionSource source,
                             GVir.Connection connection, GVir.Domain domain) {
        try {
            var machine = new LibvirtMachine (source, this, connection, domain);
            collection.add_item (machine);
            domain.set_data<LibvirtMachine> ("machine", machine);
        } catch (GLib.Error error) {
            warning ("Failed to create source '%s': %s", source.name, error.message);
        }
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
            add_domain (source, connection, domain);
        });

        connections.insert (source.name, connection);
    }

    public async void add_collection_source (CollectionSource source) {
        switch (source.source_type) {
        case "libvirt":
            yield setup_libvirt (source);
            break;

        case "vnc":
        case "spice":
            var machine = new RemoteMachine (source, this);
            collection.add_item (machine);
            break;

        default:
            warning ("Unsupported source type %s", source.source_type);
            break;
        }
    }

    private async void setup_sources () {
        if (!has_pkgconfig_sources ()) {
            var src = File.new_for_path (get_pkgdata_source ("QEMU_Session"));
            var dst = File.new_for_path (get_pkgconfig_source ("QEMU Session"));
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
            return;
        }

        var dir = File.new_for_path (get_pkgconfig_source ());
        get_sources_from_dir.begin (dir);
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

        display_page = new DisplayPage (this);
        notebook.append_page (display_page.widget, null);

        stage = embed.get_stage () as Clutter.Stage;
        stage.set_color (gdk_rgba_to_clutter_color (get_boxes_bg_color ()));

        state = new Clutter.State ();
        state.set_duration (null, null, duration);

        window.delete_event.connect (() => { return quit (); });

        window.key_press_event.connect (on_key_pressed);

        box_table = new Clutter.TableLayout ();
        box = new Clutter.Box (box_table);
        box.add_constraint (new Clutter.BindConstraint (stage, BindCoordinate.SIZE, 0));
        stage.add_actor (box);

        sidebar = new Sidebar (this);
        view = new CollectionView (this, sidebar.category);
        topbar = new Topbar (this);
        notificationbar = new Notificationbar (this);
        notificationbar.actor.add_constraint (new Clutter.AlignConstraint (view.actor, AlignAxis.X_AXIS, 0.5f));
        var yconstraint = new Clutter.BindConstraint (topbar.actor, BindCoordinate.Y, topbar.height);
        notificationbar.actor.add_constraint (yconstraint);
        topbar.actor.notify["height"].connect (() => {
            yconstraint.set_offset (topbar.height);
        });

        selectionbar = new Selectionbar (this);
        selectionbar.actor.add_constraint (new Clutter.AlignConstraint (view.actor, AlignAxis.X_AXIS, 0.5f));
        yconstraint = new Clutter.BindConstraint (view.actor, BindCoordinate.Y,
                                                  view.actor.height - selectionbar.spacing);
        selectionbar.actor.add_constraint (yconstraint);
        view.actor.notify["height"].connect (() => {
            yconstraint.set_offset (view.actor.height - selectionbar.spacing);
        });
        notebook.show_all ();

        wizard = new Wizard (this);
        properties = new Properties (this);

        ui_state = UIState.COLLECTION;
    }

    private void set_main_ui_state (string clutter_state) {
        notebook.page = Boxes.AppPage.MAIN;
        box.set_layout_manager (box_table);
        state.set_state (clutter_state);
    }

    public override void ui_state_changed () {
        box.set_layout_manager (box_table);
        action_fullscreen.set_enabled (ui_state == UIState.DISPLAY);
        action_properties.set_enabled (ui_state == UIState.DISPLAY);

        foreach (var ui in new Boxes.UI[] { sidebar, topbar, view, wizard, properties }) {
            ui.ui_state = ui_state;
        }

        switch (ui_state) {
        case UIState.DISPLAY:
            box.set_layout_manager (new Clutter.FixedLayout ());
            state.set_state (fullscreen ? "display-fullscreen" : "display");
            break;

        case UIState.CREDS:
            set_main_ui_state ("creds");
            break;

        case UIState.COLLECTION:
            set_main_ui_state ("collection");
            actor_unpin (topbar.actor);
            actor_unpin (view.actor);
            actor_remove (topbar.actor);
            actor_remove (sidebar.actor);
            actor_remove (view.actor);
            box.pack (topbar.actor, "column", 0, "row", 0,
                      "x-expand", true, "y-expand", false);
            box.pack (view.actor, "column", 0, "row", 1,
                      "x-expand", true, "y-expand", true);
            if (current_item is Machine) {
                var machine = current_item as Machine;

                machine.disconnect_display ();
                machine.update_screenshot.begin ();
            }
            break;

        case UIState.PROPERTIES:
        case UIState.WIZARD:
            actor_remove (topbar.actor);
            actor_remove (sidebar.actor);
            actor_remove (view.actor);
            box.pack (topbar.actor, "column", 0, "row", 0, "column-span", 2,
                      "x-expand", true, "y-expand", false);
            box.pack (sidebar.actor, "column", 0, "row", 1,
                      "x-expand", false, "y-expand", true);
            box.pack (view.actor, "column", 1, "row", 1,
                      "x-expand", true, "y-expand", true);
            set_main_ui_state ("collection");
            break;

        default:
            warning ("Unhandled UI state %s".printf (ui_state.to_string ()));
            break;
        }
    }

    public bool quit () {
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
                                            ngettext ("%u box has been deleted", "%u boxes have been deleted", num_selected).printf (num_selected);
        foreach (var item in selected_items)
            view.remove_item (item);

        Notificationbar.ActionFunc undo = () => {
            foreach (var selected in selected_items)
                view.add_item (selected);
        };

        Notificationbar.IgnoreFunc really_remove = () => {
            foreach (var selected in selected_items) {
                var machine = selected as Machine;

                if (machine != null)
                    machine.delete ();
            }
        };

        notificationbar.display (Gtk.Stock.UNDO, message, (owned) undo, (owned) really_remove);
    }

    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        if (event.keyval == F11_KEY) {
            fullscreen = !fullscreen;
            return true;
        }

        return false;
    }

    public bool item_selected (CollectionItem item) {
        if (ui_state == UIState.COLLECTION && !selection_mode) {
            current_item = item;

            if (current_item is Machine) {
                var machine = current_item as Machine;

                machine.connect_display ();
                ui_state = UIState.CREDS;
            } else
                warning ("unknown item, fix your code");
        }

        return false;
    }
}

