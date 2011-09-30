using GLib;
using Clutter;
using Spice;
using GVir;

	// private void setup_spice_display () {
    //     var s = new Spice.Session ();
    //     var d = new Spice.Display (s, 0);
	// }

class Box: CollectionItem {
    public BoxActor actor;

	GVir.Domain domain;

    public Box (GVir.Domain domain) {
		this.domain = domain;
        this.name = domain.get_name ();
        actor = new BoxActor (this);
    }

    public Clutter.Actor get_clutter_actor () {
        return actor.actor;
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

		try {
			var pix = new Gdk.Pixbuf.from_file ("shot.png"); // cluttertexture has lots of apis
            ctexture = new GtkClutter.Texture ();
			ctexture.set_from_pixbuf (pix);
		} catch (GLib.Error e) {
			warning (e.message);
		}

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

