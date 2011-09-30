using Config;
using Gtk;
using Gdk;
using GtkClutter;
using Clutter;
using GLib;

class Boxes: GLib.Object {
	GtkClutter.Window window;
	Clutter.Stage cstage;
	Clutter.State cstate;

	Clutter.Box cbox; // the whole app box
	Clutter.TableLayout cbox_table;

	Clutter.Actor ctopbar; // the topbar box
	Gtk.Notebook topbar;
	Gtk.HBox topbar_hbox;
	Gtk.Toolbar topbar_toolbar_start;

	Clutter.Actor csidebar; // the sidebar box
	Gtk.Notebook sidebar;

	Clutter.Box cboxes; // the boxes list box
	Clutter.FlowLayout cboxes_flow;
	Clutter.Box conebox; // a box on top of boxes list

	Box box;
	uint sidebar_width;
	uint topbar_height;

	public enum UIState {
		COLLECTION,
		CREDS,
		REMOTE,
		SETTINGS,
		WIZARD
	}
	public UIState state;

	public Boxes() {
		// window = new Gtk.Window ();
		// var bg = window.get_style ().fg[Gtk.StateType.NORMAL];
		// Clutter.Color color = { (uint8)(bg.red / 256), (uint8)(bg.green /256), (uint8)(bg.blue /256), 255 };
		// var embed = new GtkClutter.Embed ();
		// cstage.set_color (color);
		window = new GtkClutter.Window ();
		window.set_default_size (640, 480);
		cstage = (Clutter.Stage)window.get_stage ();

		window.destroy.connect (quit);
		window.key_press_event.connect (key_pressed);

		cbox_table = new Clutter.TableLayout ();
		cbox = new Clutter.Box (cbox_table);
		cbox.add_constraint (new Clutter.BindConstraint ((Clutter.Actor) cstage, BindCoordinate.SIZE, 0));
		((Clutter.Container) cstage).add_actor (cbox);

		sidebar_width = 200;
		topbar_height = 50;
		setup_topbar ();
		setup_sidebar ();
		setup_boxes ();

		window.show_all ();

		cstate = new Clutter.State ();
		cstate.set_duration (null, null, 555); // default to 1/2 for all transitions
		cstate.set_key (null, "creds", cboxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint)0, 0, 0);
		cstate.set_key (null, "remote", csidebar, "x", AnimationMode.EASE_OUT_QUAD, -(float)sidebar_width, 0, 0); // FIXME: make it dynamic depending on sidebar size..
		cstate.set_key (null, "remote", ctopbar, "y", AnimationMode.EASE_OUT_QUAD, -(float)topbar_height, 0, 0); // FIXME: make it dynamic depending on topbar size..
		cstate.set_key (null, "remote", cboxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint)0, 0, 0);
		cstate.set_key (null, "remote", conebox, "x", AnimationMode.EASE_OUT_QUAD, (float)0, 0, 0);
		cstate.set_key (null, "remote", conebox, "y", AnimationMode.EASE_OUT_QUAD, (float)0, 0, 0);
		cstate.set_key (null, "collection", cboxes, "opacity", AnimationMode.EASE_OUT_QUAD, (uint)255, 0, 0);
		set_ui_state (UIState.COLLECTION);
	}

	private void setup_boxes () {
		cboxes_flow = new Clutter.FlowLayout (Clutter.FlowOrientation.HORIZONTAL);
		cboxes = new Clutter.Box (cboxes_flow);
		cboxes_flow.set_column_spacing (35);
		cboxes_flow.set_row_spacing (25);

		for (var i = 0; i < 7; ++i) {
			var box = new Box ("vm %d".printf(i));
			var actor = box.get_clutter_actor ();
			actor.set_reactive (true);
			actor.button_press_event.connect ((actor, event) => { return item_pressed (box, event); });
			cboxes.add_actor (actor);
		}
		cbox.pack (cboxes, "column", 1, "row", 1, "x-expand", true, "y-expand", true);

		// FIXME! report bug to clutter about flow inside table
		cboxes.add_constraint_with_name ("boxes-left", new Clutter.SnapConstraint (cstage, SnapEdge.RIGHT, SnapEdge.RIGHT, 0));
		cboxes.add_constraint_with_name ("boxes-bottom", new Clutter.SnapConstraint (cstage, SnapEdge.BOTTOM, SnapEdge.RIGHT.BOTTOM, 0));

		conebox = new Clutter.Box (new Clutter.BinLayout (Clutter.BinAlignment.FILL, Clutter.BinAlignment.FILL));
		conebox.add_constraint_with_name ("onebox-size", new Clutter.BindConstraint (cboxes, BindCoordinate.SIZE, 0));
		conebox.add_constraint_with_name ("onebox-position", new Clutter.BindConstraint (cboxes, BindCoordinate.POSITION, 0));
		cstage.add_actor (conebox);
	}

	private void setup_topbar () {
		topbar = new Gtk.Notebook ();
		topbar.set_size_request (50, (int)topbar_height);
		ctopbar = new GtkClutter.Actor.with_contents (topbar);
		cbox.pack (ctopbar, "column", 1, "row", 0, "x-expand", true, "y-expand", false);

		topbar_hbox = new Gtk.HBox (false, 10);

		topbar_toolbar_start = new Gtk.Toolbar ();
		topbar_toolbar_start.icon_size = Gtk.IconSize.MENU;
        topbar_toolbar_start.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        var back = new Gtk.ToolButton (null, null);
		back.icon_name =  "go-previous-symbolic";
        back.get_style_context ().add_class ("raised");
		back.clicked.connect ( (button) => { go_back (); });
        topbar_toolbar_start.insert (back, 0);
		topbar_toolbar_start.set_show_arrow (false);
		topbar_hbox.pack_start (topbar_toolbar_start, false, false, 0);

		var label = new Gtk.Label ("New and recent");
		label.set_halign (Gtk.Align.START);
		topbar_hbox.pack_start (label, true, true, 0);

		var topbar_toolbar_end = new Gtk.Toolbar ();
		topbar_toolbar_end.icon_size = Gtk.IconSize.MENU;
        topbar_toolbar_end.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        var spinner = new Gtk.ToolButton (new Gtk.Spinner (), null);
        spinner.get_style_context ().add_class ("raised");
        topbar_toolbar_end.insert (spinner, 0);
		topbar_toolbar_end.set_show_arrow (false);
		topbar_hbox.pack_start (topbar_toolbar_end, false, false, 0);

		topbar.append_page (topbar_hbox, null);
		topbar.page = 0;
		topbar.show_tabs = false;
		topbar.show_all ();
	}

	private void setup_sidebar () {
		sidebar = new Gtk.Notebook ();
		sidebar.set_size_request ((int)sidebar_width, 200);

		var view = new Gtk.TreeView ();
		sidebar.append_page (view, new Gtk.Label ("foo"));
		sidebar.page = 0;
		sidebar.show_tabs = false;
		sidebar.show_all ();
		csidebar = new GtkClutter.Actor.with_contents (sidebar);
		cbox.pack (csidebar, "column", 0, "row", 1, "x-expand", false, "y-expand", true);

		var listmodel = new ListStore (3, typeof (string), typeof (uint), typeof (bool));
		view.set_model (listmodel);
		view.headers_visible = false;
		view.insert_column_with_attributes (-1, "Collection", new CellRendererText (), "text", 0, "height", 1, "sensitive", 2);

        TreeIter iter;
        listmodel.append (out iter);
        listmodel.set (iter, 0, "New and recent");
        listmodel.set (iter, 2, true);
        listmodel.append (out iter);
        listmodel.set (iter, 0, "Favorites");
        listmodel.set (iter, 2, true);
        listmodel.append (out iter);
        listmodel.set (iter, 0, "Private");
        listmodel.set (iter, 2, true);
        listmodel.append (out iter);
        listmodel.set (iter, 0, "Shared");
        listmodel.set (iter, 2, true);
        listmodel.append (out iter);
        listmodel.set (iter, 0, "Collections");
        listmodel.set (iter, 1, (uint)40);
        listmodel.set (iter, 2, false);
        listmodel.append (out iter);
        listmodel.set (iter, 0, "Work");
        listmodel.set (iter, 2, true);
        listmodel.append (out iter);
        listmodel.set (iter, 0, "Game");
        listmodel.set (iter, 2, true);
	}

	void set_ui_state (UIState state) {
		message ("Switching layout to %s".printf (state.to_string ()));

		// to pin actor position, keepme
		foreach (var a in new Clutter.Actor[] { ctopbar, cboxes, csidebar, conebox }) {
			var g = a.get_geometry ();
			a.set_geometry (g);
		}

		if (state == UIState.REMOTE) {
			int w, h;
			window.get_size (out w, out h);

			cbox.set_layout_manager (new Clutter.FixedLayout ());
			cboxes.set_layout_manager (new Clutter.FixedLayout ());
			cstate.set_state ("remote");

			box.actor.ctexture.animate (Clutter.AnimationMode.LINEAR, 555,
										"width", (float)w,
										"height", (float)h);
			box.actor.actor.animate (Clutter.AnimationMode.LINEAR, 555,
									 "x", 0.0f,
									 "y", 0.0f);
		}
		else if (state == UIState.CREDS) {
			topbar_toolbar_start.show ();
			cbox.set_layout_manager (cbox_table);
			cboxes.set_layout_manager (new Clutter.FixedLayout ());
			cstate.set_state ("creds");
		}
		else if (state == UIState.COLLECTION) {
			topbar_toolbar_start.hide ();
			cbox.set_layout_manager (cbox_table);
			cboxes.set_layout_manager (cboxes_flow);
			cstate.set_state ("collection");
		}

		this.state = state;
	}

	private void go_back () {
		var actor = box.actor;
		var cactor = actor.actor;

		conebox.remove_actor (cactor);
		actor.scale_texture ();
		actor.entry.set_can_focus (false);
		actor.entry.hide ();

		cboxes.add_actor (cactor);

		set_ui_state (UIState.COLLECTION);
	}

	bool key_pressed (Gtk.Widget widget, Gdk.EventKey event) {
		// damn widget parent is not a gdkwindow..
		if (event.keyval == Gdk.Key.F11) {
			window.fullscreen ();
			return true;
		}
		return false;
	}

	bool item_pressed (Box box, Clutter.ButtonEvent event) {
		var actor = box.actor;
		var cactor = actor.actor;

		if (state == UIState.COLLECTION) {
			set_ui_state (UIState.CREDS);

			this.box = box;
			cboxes.remove_actor (cactor);

			actor.scale_texture (2.0f);
			actor.entry.show ();
//		actor.entry.set_sensitive (false); FIXME: depending on spice-gtk conn. results
			actor.entry.set_can_focus (true);
			actor.entry.grab_focus ();

			conebox.pack (cactor,
						  "x-align", Clutter.BinAlignment.CENTER,
						  "y-align", Clutter.BinAlignment.CENTER);

		} else if (state == UIState.CREDS) {
			float x, y;

			actor.entry.hide ();
			actor.label.hide ();

			cactor.get_transformed_position (out x, out y);
			conebox.remove_actor (cactor);
			cstage.add_actor (cactor);
			cactor.set_position (x, y);
			set_ui_state (UIState.REMOTE);
		}

		return false;
	}

	public void quit () {
		Gtk.main_quit ();
	}

	public static void main (string[] args) {
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

class BoxActor: GLib.Object {
	public Clutter.Box actor;

	public GtkClutter.Texture ctexture; // the texture
	public Gtk.VBox vbox; // and the vbox under it
	public Gtk.Entry entry;
	public Gtk.Label label;

	public BoxActor (Box box) {
		var layout = new Clutter.BoxLayout ();
		layout.vertical = true;
		var cbox = new Clutter.Box (layout);

		var pix = new Gdk.Pixbuf.from_file ("shot.png"); // cluttertexture has lots of apis
		ctexture = new GtkClutter.Texture ();
		ctexture.set_from_pixbuf (pix);
		scale_texture ();
		cbox.add_actor (ctexture);
		ctexture.keep_aspect_ratio = true;

		var gtkactor = new GtkClutter.Actor ();
		var bin = (Gtk.Bin)gtkactor.get_widget ();
		vbox = new Gtk.VBox (false, 0);
		label = new Gtk.Label (box.name);
		vbox.add (label);
		entry = new Gtk.Entry ();
		entry.set_visibility (false);
		entry.set_placeholder_text ("Password"); // TODO: i18n stupid vala...
		vbox.add (entry);
		bin.add (vbox);

		bin.show_all ();
		entry.hide ();

		cbox.add_actor (gtkactor);

		actor = cbox;
	}

	public void scale_texture (float scale = 1.5f) {
		ctexture.set_size (128 * scale, 96 * scale);
	}
}

class Box: GLib.Object {
	public BoxActor actor;
	public string name;

	public Box (string name) {
		this.name = name;
		actor = new BoxActor (this);
	}

	public Clutter.Actor get_clutter_actor () {
		return actor.actor;
	}
}

