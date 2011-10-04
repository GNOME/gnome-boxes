// This file is part of GNOME Boxes. License: LGPL2
using Config;
using Gtk;
using Gdk;
using GtkClutter;
using Clutter;
using GLib;
using GVir;

// FIXME: vala includes header incorrectly, this will make sure config.h comes on top...
static const string foo = GNOMELOCALEDIR;

private enum Boxes.UIState {
    COLLECTION,
    CREDS,
    DISPLAY,
    SETTINGS,
    WIZARD
}

private errordomain Boxes.Error {
    INVALID
}

private class Boxes.App: Boxes.UI {
    // FIXME: Remove these when we can use Vala release that provides binding for gdkkeysyms.h
    private const uint F11_KEY = 0xffc8;
    private const uint F12_KEY = 0xffc9;

    public Gtk.Window window;
    public GtkClutter.Embed embed;
    public Stage stage;
    public Clutter.State state;
    public Clutter.Box box; // the whole app box
    public Box selected_box; // currently selected box
    public GVir.Connection connection;
    public static const uint duration = 555;  // default to 1/2 for all transitions

    private Clutter.TableLayout box_table;
    private Collection collection;
    private Sidebar sidebar;
    private Topbar topbar;
    private CollectionView view;

    public static void main (string[] args) {
        Intl.bindtextdomain (GETTEXT_PACKAGE, GNOMELOCALEDIR);
        Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (GETTEXT_PACKAGE);
        GLib.Environment.set_application_name (_("GNOME Boxes"));

        GtkClutter.init (ref args);

        Gtk.Window.set_default_icon_name ("gnome-boxes");
        Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;
        var provider = new Gtk.CssProvider ();
        try {
            var sheet = get_style ("gtk-style.css");
            provider.load_from_path (sheet);
            Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (),
                                                      provider,
                                                      600);
        } catch (GLib.Error e) {
            warning (e.message);
        }

        new App ();
        Gtk.main ();
    }

    public App() {
        setup_ui ();
        collection = new Collection ();

        collection.item_added.connect((item) => {
            if (item is Box) {
                var box = item as Box;
                var actor = box.get_clutter_actor ();
                actor.set_reactive (true);
                actor.button_press_event.connect ((actor, event) => { return box_clicked (box, event); });
            }

            view.add_item (item);
        });

        setup_libvirt.begin ();
    }

    public void set_category (Category category) {
        topbar.label.set_text (category.name);
    }

    private async void setup_libvirt () {
        connection = new GVir.Connection ("qemu:///system");

        try {
            yield connection.open_async (null);
            connection.fetch_domains (null);
        } catch (GLib.Error e) {
            warning (e.message);
        }

        foreach (var domain in connection.get_domains ()) {
            var box = new Box (this, domain);
            collection.add_item (box);
        }
    }

    private void setup_ui () {
        window = new Gtk.Window ();
        window.set_default_size (640, 480);
        embed = new GtkClutter.Embed ();
        embed.show ();
        window.add (embed);
        stage = embed.get_stage () as Clutter.Stage;

        var actor = new GtkClutter.Actor (); // just to have background
        actor.add_constraint (new Clutter.BindConstraint ((Clutter.Actor) stage, BindCoordinate.SIZE, 0));
        ((Clutter.Container) stage).add_actor (actor);

        state = new Clutter.State ();
        state.set_duration (null, null, duration);

        window.destroy.connect (quit);
        window.key_press_event.connect (on_key_pressed);
        window.configure_event.connect ( (event) => {
            if (event.type == Gdk.EventType.CONFIGURE)
                save_window_size ();

            return false;
        });

        box_table = new Clutter.TableLayout ();
        box = new Clutter.Box (box_table);
        box.add_constraint (new Clutter.BindConstraint ((Clutter.Actor) stage, BindCoordinate.SIZE, 0));
        ((Clutter.Container) stage).add_actor (box);

        topbar = new Topbar (this);
        sidebar = new Sidebar (this);
        view = new CollectionView (this);

        var size_group = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
        size_group.add_widget (topbar.corner);
        size_group.add_widget (sidebar.notebook);

        window.show ();

        ui_state = UIState.COLLECTION;
    }

    public void go_back () {
        ui_state = UIState.COLLECTION;
        selected_box = null;
    }

    public override void ui_state_changed () {
        message ("Switching layout to %s".printf (ui_state.to_string ()));

        foreach (var o in new Boxes.UI[] { sidebar, topbar, view }) {
            o.ui_state = ui_state;
        }

        box.set_layout_manager (box_table);

        switch (ui_state) {
        case UIState.DISPLAY:
            box.set_layout_manager (new Clutter.FixedLayout ());
            state.set_state ("display");
            break;
        case UIState.CREDS:
            state.set_state ("creds");
            break;
        case UIState.COLLECTION:
            restore_window_size ();
            state.set_state ("collection");
            break;
        default:
            warning ("Unhandled UI state %s".printf (ui_state.to_string ()));
            break;
        }
    }

    public void save_window_size () {
        float w, h;

		if (ui_state == UIState.DISPLAY)
			return;

        window.get_size (out w, out h);
        window.default_width = (int)w;
        window.default_height = (int)h;
    }

    public void restore_window_size () {
        window.resize (window.default_width, window.default_height);
    }

    public void set_window_size (int width, int height, bool save=false) {
        if (save)
            save_window_size ();
        window.resize (width, height);
    }

    public void quit () {
        Gtk.main_quit ();
    }

    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        if (event.keyval == F11_KEY) {
            if (WindowState.FULLSCREEN in window.get_window ().get_state ())
                window.unfullscreen ();
            else
                window.fullscreen ();

            return true;
        }

        if (event.keyval == F12_KEY) {
            ui_state = UIState.COLLECTION;
        }

        return false;
    }

    private bool box_clicked (Box box, Clutter.ButtonEvent event) {
        if (ui_state == UIState.COLLECTION) {
            selected_box = box;
            if (selected_box.connect_display ())
                ui_state = UIState.CREDS;
        }

        return false;
    }
}

private abstract class Boxes.UI: GLib.Object {
    public UIState ui_state { get; set; }

    public UI () {
        notify["ui-state"].connect ( (s, p) => {
            ui_state_changed ();
        });
    }

    public void pin_actor (Clutter.Actor actor) {
        actor.set_geometry (actor.get_geometry ());
    }

    public abstract void ui_state_changed ();
}
