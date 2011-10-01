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
    public DomainState state { get {
            try {
                return domain.get_info ().state;
            } catch (GLib.Error e) {
                return DomainState.NONE;
            }
        }
    }

    Boxes boxes;
    GVir.Domain domain;

    public Box (Boxes boxes, GVir.Domain domain) {
        this.boxes = boxes;
        this.domain = domain;

        this.name = domain.get_name ();
        actor = new BoxActor (this);
        Timeout.add_seconds (1, () => {
                take_screenshot.begin ();
                return false; //fixme
            });
    }

    public Clutter.Actor get_clutter_actor () {
        return actor.actor;
    }

    public string get_screenshot_filename (string ext = "png") {
        var uuid = domain.get_uuid ();
        return get_pkgcache (uuid + "-screenshot." + ext);
    }

    private async int write_screenshot (GLib.FileOutputStream s, uint8[] buf) {
        try {
            return (int)yield s.write_async (buf);
        } catch (GLib.Error e) {
            warning (e.message);
        }
        return -1;
    }

    public async bool take_screenshot () {

        if (state != DomainState.RUNNING &&
            state != DomainState.PAUSED)
            return false;

        var st = boxes.conn.get_stream (0);
        var fname = get_screenshot_filename ();
        var file = File.new_for_path (fname);
        try {
            var f = yield file.open_readwrite_async ();
            f.truncate (0);
            var o = f.get_output_stream ();
            var i = st.get_input_stream ();
            domain.screenshot (st, 0, 0);

            var b = new uint8[65535];
            ssize_t l = 0;
            do {
                l = yield i.read_async (b);
                yield output_stream_write (o, b[0:l]);
            } while (l > 0);

        } catch (GLib.Error e) {
            warning (e.message);
        }

        return true;
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

