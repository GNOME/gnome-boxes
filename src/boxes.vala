using Config;
using Gtk;
using Gdk;
using GtkClutter;
using Clutter;
using GLib;
using GVir;

public enum UIState {
	COLLECTION,
	CREDS,
	REMOTE,
	SETTINGS,
	WIZARD
}

class Boxes: BoxesUI {
    public Gtk.Window window;
	public GtkClutter.Embed embed;
    public Clutter.Stage cstage;
    public Clutter.State cstate;
    public Clutter.Box cbox; // the whole app box
    public Box? box; // currently selected box

    Clutter.TableLayout cbox_table;

	Collection collection;
	Sidebar sidebar;
	Topbar topbar;
	CollectionView view;

    public Boxes() {
		setup_ui ();
		collection = new Collection ();

		collection.item_added.connect( (item) => {
				if (item is Box) {
					var box = (Box)item;
					var actor = box.get_clutter_actor ();
					actor.set_reactive (true);
					actor.button_press_event.connect ((actor, event) => { return box_clicked (box, event); });
				}

				view.add_item (item);
			});

		setup_libvirt.begin ();
    }

	private async void setup_libvirt () {
		var c = new GVir.Connection("qemu:///system");

		try {
			yield c.open_async (null);
			c.fetch_domains(null);
		} catch (GLib.Error e) {
			warning (e.message);
		}

		foreach (var d in c.get_domains()) {
			var box = new Box (d);
			collection.add_item (box);
		}
	}

	private void setup_ui () {
        window = new Gtk.Window ();
        window.set_default_size (640, 480);
		embed = new GtkClutter.Embed ();
		embed.show ();
		window.add (embed);
        cstage = (Clutter.Stage)embed.get_stage ();

		var a = new GtkClutter.Actor (); // just to have background
		a.add_constraint (new Clutter.BindConstraint ((Clutter.Actor) cstage, BindCoordinate.SIZE, 0));
		((Clutter.Container) cstage).add_actor (a);

        cstate = new Clutter.State ();
        cstate.set_duration (null, null, 555); // default to 1/2 for all transitions

        window.destroy.connect (quit);
        window.key_press_event.connect (key_pressed);

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

        set_ui_state (UIState.COLLECTION);
	}

    void set_ui_state (UIState state) {
        message ("Switching layout to %s".printf (state.to_string ()));
        this.ui_state = state;

        if (state == UIState.REMOTE) {
			cbox.set_layout_manager (new Clutter.FixedLayout ());
		} else {
			cbox.set_layout_manager (cbox_table);
		}
    }

    bool key_pressed (Gtk.Widget widget, Gdk.EventKey event) {
        // damn widget parent is not a gdkwindow..
        if (event.keyval == Gdk.Key.F11) {
            window.fullscreen ();
            return true;
        }
        return false;
    }

    bool box_clicked (Box box, Clutter.ButtonEvent event) {
        if (ui_state == UIState.COLLECTION) {
            this.box = box;
            set_ui_state (UIState.CREDS);
        } else if (ui_state == UIState.CREDS) {
            set_ui_state (UIState.REMOTE);
        }

        return false;
    }

    public void go_back () {
		set_ui_state (UIState.COLLECTION);
        box = null;
    }

	public override void ui_state_changed() {
		foreach (var o in new BoxesUI[] { sidebar, topbar, view }) {
			o.ui_state = ui_state;
		}

        switch (ui_state) {
		case UIState.REMOTE:
			cstate.set_state ("remote");
			break;
		case UIState.CREDS:
			cstate.set_state ("creds");
			break;
		case UIState.COLLECTION:
			cstate.set_state ("collection");
			break;
		default:
			warning ("Unhandled UI state %s".printf (ui_state.to_string ()));
			break;
		}
	}

    public void quit () {
        Gtk.main_quit ();
    }

    public static void main (string[] args) {
		// FIXME: vala...
        // Intl.bindtextdomain (GETTEXT_PACKAGE, GNOMELOCALEDIR);
        // Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
        // Intl.textdomain (GETTEXT_PACKAGE);
        // GLib.Environment.set_application_name (_("Boxes"));

        GtkClutter.init (ref args);
        Gtk.Window.set_default_icon_name ("boxes");
        Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;

        var boxes = new Boxes ();
        Gtk.main ();
    }
}

public abstract class BoxesUI: GLib.Object {
	public UIState ui_state { get; set; }

	public BoxesUI() {
		this.notify["ui-state"].connect((s, p) => {
				ui_state_changed();
			});
	}

	public void pin_actor (Clutter.Actor a) {
		a.set_geometry (a.get_geometry ());
	}

	public abstract void ui_state_changed();
}
