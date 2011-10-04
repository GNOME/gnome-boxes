using Config;
using Gtk;
using Gdk;
using GtkClutter;
using Clutter;
using GLib;
using GVir;

// FIXME: vala includes header incorrectly, this will make sure config.h comes on top...
static const string foo = GNOMELOCALEDIR;

public enum Boxes.UIState {
    COLLECTION,
    CREDS,
    DISPLAY,
    SETTINGS,
    WIZARD
}

public errordomain Boxes.Error {
    INVALID
}

class Boxes.App: Boxes.UI {
    // FIXME: Remove these when we can use Vala release that provides binding for gdkkeysyms.h
    private const uint F11_KEY = 0xffc8;
    private const uint F12_KEY = 0xffc9;

    public Gtk.Window window;
    public GtkClutter.Embed embed;
    public Clutter.Stage cstage;
    public Clutter.State cstate;
    public Clutter.Box cbox; // the whole app box
    public Box? box; // currently selected box
    public GVir.Connection conn;
    public static const uint duration = 555;  // default to 1/2 for all transitions

    Clutter.TableLayout cbox_table;
    Collection collection;
    Sidebar sidebar;
    Topbar topbar;
    CollectionView view;

    public App() {
        setup_ui ();
        collection = new Collection ();

        collection.item_added.connect( (item) => {
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

    private async void setup_libvirt () {
        conn = new GVir.Connection ("qemu:///system");

        try {
            yield conn.open_async (null);
            conn.fetch_domains (null);
        } catch (GLib.Error e) {
            warning (e.message);
        }

        foreach (var d in conn.get_domains ()) {
            var box = new Box (this, d);
            collection.add_item (box);
        }
    }

    private void setup_ui () {
        window = new Gtk.Window ();
        window.set_default_size (640, 480);
        embed = new GtkClutter.Embed ();
        embed.show ();
        window.add (embed);
        cstage = embed.get_stage () as Clutter.Stage;

        var a = new GtkClutter.Actor (); // just to have background
        a.add_constraint (new Clutter.BindConstraint ((Clutter.Actor) cstage, BindCoordinate.SIZE, 0));
        ((Clutter.Container) cstage).add_actor (a);

        cstate = new Clutter.State ();
        cstate.set_duration (null, null, duration);

        window.destroy.connect (quit);
        window.key_press_event.connect (key_pressed);
        window.configure_event.connect ( (event) => {
                if (event.type == Gdk.EventType.CONFIGURE)
                    save_window_size ();
                return false;
            });

        cbox_table = new Clutter.TableLayout ();
        cbox = new Clutter.Box (cbox_table);
        cbox.add_constraint (new Clutter.BindConstraint ((Clutter.Actor) cstage, BindCoordinate.SIZE, 0));
        ((Clutter.Container) cstage).add_actor (cbox);

        topbar = new Topbar (this);
        sidebar = new Sidebar (this);
        view = new CollectionView (this);

        var sg = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
        sg.add_widget (topbar.corner);
        sg.add_widget (sidebar.notebook);

        window.show ();

        ui_state = UIState.COLLECTION;
    }

    public void set_category (Category category) {
        topbar.label.set_text (category.name);
    }

    bool key_pressed (Gtk.Widget widget, Gdk.EventKey event) {
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

    bool box_clicked (Box box, Clutter.ButtonEvent event) {
        if (ui_state == UIState.COLLECTION) {
            this.box = box;
            if (this.box.connect_display ())
                ui_state = UIState.CREDS;
        }

        return false;
    }

    public void go_back () {
        ui_state = UIState.COLLECTION;
        box = null;
    }

    public override void ui_state_changed () {
        message ("Switching layout to %s".printf (ui_state.to_string ()));

        foreach (var o in new Boxes.UI[] { sidebar, topbar, view }) {
            o.ui_state = ui_state;
        }

        cbox.set_layout_manager (cbox_table);

        switch (ui_state) {
        case UIState.DISPLAY:
            cbox.set_layout_manager (new Clutter.FixedLayout ());
            cstate.set_state ("display");
            break;
        case UIState.CREDS:
            cstate.set_state ("creds");
            break;
        case UIState.COLLECTION:
            restore_window_size ();
            cstate.set_state ("collection");
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
}

public abstract class Boxes.UI: GLib.Object {
    public UIState ui_state { get; set; }

    public UI () {
        this.notify["ui-state"].connect ( (s, p) => {
                ui_state_changed ();
            });
    }

    public void pin_actor (Clutter.Actor a) {
        a.set_geometry (a.get_geometry ());
    }

    public abstract void ui_state_changed ();
}
