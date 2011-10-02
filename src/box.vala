using GLib;
using Clutter;
using Gdk;
using Gtk;
using GVir;

abstract class Boxes.Display: GLib.Object {
//    public bool need_password = false;
    protected HashTable<int, Gtk.Widget?> displays = new HashTable<int, Gtk.Widget> (direct_hash, direct_equal);

    public signal void show (int displayid);
    public signal void hide (int displayid);
    public signal void disconnected ();

    public abstract Gtk.Widget get_display (int n) throws Boxes.Error;
    public abstract void connect_it ();
    public abstract void disconnect_it ();

    ~Boxes() {
        disconnect_it ();
    }
}

class Boxes.Box: Boxes.CollectionItem {
    public Boxes.App app;
    public BoxActor actor;
    public DomainState state { get {
            try {
                return domain.get_info ().state;
            } catch (GLib.Error e) {
                return DomainState.NONE;
            }
        }
    }

    Display? display;

    GVir.Domain _domain;
    public GVir.Domain domain {
        get { return _domain; }
        construct set {
            this._domain = value;
        }
    }

    public Box (Boxes.App app, GVir.Domain domain) {
        Object (domain: domain);
        this.app = app;

        name = domain.get_name ();
        actor = new BoxActor (this);

        update_screenshot.begin ();
        Timeout.add_seconds (5, () => {
                update_screenshot.begin ();
                return true;
            });

        app.cstate.completed.connect ( () => {
                if (app.cstate.state == "display") {
                    if (app.box != this)
                        return;

                    try {
                        actor.show_display (display.get_display (0));
                    } catch (Boxes.Error e) {
                        warning (e.message);
                    }
                }
            });
    }

    public Clutter.Actor get_clutter_actor () {
        return actor.actor;
    }

    private string get_screenshot_filename (string ext = "ppm") {
        var uuid = domain.get_uuid ();
        return get_pkgcache (uuid + "-screenshot." + ext);
    }

    private async void update_screenshot () {
        Gdk.Pixbuf? pix = null;

        try {
            yield take_screenshot ();
            pix = new Gdk.Pixbuf.from_file (get_screenshot_filename ());
        } catch (GLib.Error e) {
            if (!(e is FileError.NOENT))
                warning (e.message);
        }

        if (pix == null)
            pix = draw_fallback_vm (128, 96);

        try {
            actor.set_screenshot (pix);
        } catch (GLib.Error err) {
            warning (err.message);
        }
    }

    public async bool take_screenshot () throws GLib.Error {

        if (state != DomainState.RUNNING &&
            state != DomainState.PAUSED)
            return false;

        var st = app.conn.get_stream (0);
        var fname = get_screenshot_filename ();
        var file = File.new_for_path (fname);
        var o = yield file.replace_async (null, false, FileCreateFlags.REPLACE_DESTINATION);
        var i = st.get_input_stream ();
        domain.screenshot (st, 0, 0);

        var b = new uint8[65535];
        ssize_t l = 0;
        do {
            l = yield i.read_async (b);
            yield output_stream_write (o, b[0:l]);
        } while (l > 0);

        return true;
    }

    private static Gdk.Pixbuf draw_fallback_vm (int w, int h) {
        Gdk.Pixbuf pixbuf = null;

        try {
            var cst = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (cst);

            var pat = new Cairo.Pattern.linear (0, 0, 0, h);
            pat.add_color_stop_rgb (0, 0.260, 0.260, 0.260);
            pat.add_color_stop_rgb (1, 0.220, 0.220, 0.220);

            cr.set_source (pat);
            cr.paint ();

            int size = (int)(h * 0.5);
            var icon_info = IconTheme.get_default ().lookup_icon ("computer-symbolic", size,
                                                                IconLookupFlags.GENERIC_FALLBACK);
            Gdk.cairo_set_source_pixbuf (cr, icon_info.load_icon (),
                                         (w - size) / 2, (h - size) / 2);
            cr.rectangle ((w - size) / 2, (h - size) / 2, size, size);
            cr.fill ();
            pixbuf = Gdk.pixbuf_get_from_surface (cst, 0, 0, w, h);
        } catch {
        }

        if (pixbuf != null)
            return pixbuf;

        var cst = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
        return Gdk.pixbuf_get_from_surface (cst, 0, 0, w, h);
    }

    public bool connect_display () {
        update_display ();

        if (display == null)
            return false;

        display.connect_it ();
        return true;
    }

    private void update_display () {
        string? type, gport, socket, ghost;

        try {
            var xmldoc = domain.get_config (0).doc;
            type = extract_xpath (xmldoc, "string(/domain/devices/graphics/@type)", true);
            gport = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@port)");
            socket = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@socket)");
            ghost = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@listen)");
        } catch (GLib.Error e) {
            warning (e.message);
            return;
        }

        if (type == "spice") {
            display = new SpiceDisplay (ghost, gport.to_int ());
        } else {
            warning ("unsupported display of type " + type);
            return;
        }

        display.show.connect ( (id) => {
                app.ui_state = Boxes.UIState.DISPLAY;
            });
        display.disconnected.connect ( () => {
                app.ui_state = Boxes.UIState.COLLECTION;
            });
    }
}

class Boxes.BoxActor: Boxes.UI {
    public Clutter.Box actor;

    GtkClutter.Texture screenshot;
    GtkClutter.Actor gtkactor;
    Gtk.Label label;
    Gtk.VBox vbox; // and the vbox under it
    Gtk.Entry entry;
    Gtk.Widget? display;
    Box box;

    ulong wrsid; ulong hrsid; // signal handlers

    public BoxActor (Box box) {
        this.box = box;

        var layout = new Clutter.BoxLayout ();
        layout.vertical = true;
        var cbox = new Clutter.Box (layout);

        screenshot = new GtkClutter.Texture ();
        screenshot.name = "screenshot";

        scale_screenshot ();
        actor_add (screenshot, cbox);
        screenshot.keep_aspect_ratio = true;

        vbox = new Gtk.VBox (false, 0);
        gtkactor = new GtkClutter.Actor.with_contents (vbox);
        label = new Gtk.Label (box.name);
        vbox.add (label);
        entry = new Gtk.Entry ();
        entry.set_visibility (false);
        entry.set_placeholder_text ("Password"); // TODO: i18n stupid vala...
        vbox.add (entry);

        vbox.show_all ();
        entry.hide ();

        actor_add (gtkactor, cbox);

        actor = cbox;
    }

    public void scale_screenshot (float scale = 1.5f) {
        screenshot.set_size (128 * scale, 96 * scale);
    }

    public void set_screenshot (Gdk.Pixbuf pix) throws GLib.Error {
        screenshot.set_from_pixbuf (pix);
    }

    void update_display_size () {
        if (display.width_request < 320 || display.height_request < 200) {
            // filter invalid size request
            // TODO: where does it come from
            return;
        }

        box.app.set_window_size (display.width_request, display.height_request);
    }

    public void show_display (Gtk.Widget display) {
        if (this.display != null) {
            warning ("This box actor already contains a display");
            return;
        }

        actor_remove (screenshot);

        this.display = display;
        wrsid = display.notify["width-request"].connect ( (pspec) => {
                update_display_size ();
            });
        hrsid = display.notify["height-request"].connect ( (pspec) => {
                update_display_size ();
            });
        vbox.add (display);
        update_display_size ();

        display.show ();
        display.grab_focus ();
    }

    public void hide_display () {
        if (display == null)
            return;

        vbox.remove (display);
        display.disconnect (wrsid);
        display.disconnect (hrsid);
        display = null;

        actor.pack_at (screenshot, 0);
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.CREDS: {
            scale_screenshot (2.0f);
            entry.show ();
            // actor.entry.set_sensitive (false); FIXME: depending on spice-gtk conn. results
            entry.set_can_focus (true);
            entry.grab_focus ();
            break;
        }
        case UIState.DISPLAY: {
            int w, h;

            entry.hide ();
            label.hide ();
            box.app.window.get_size (out w, out h);
            screenshot.animate (Clutter.AnimationMode.LINEAR, Boxes.App.duration,
                                "width", (float)w,
                                "height", (float)h);
            actor.animate (Clutter.AnimationMode.LINEAR, Boxes.App.duration,
                           "x", 0.0f,
                           "y", 0.0f);
            break;
        }
        case UIState.COLLECTION: {
            hide_display ();
            scale_screenshot ();
            entry.set_can_focus (false);
            entry.hide ();
            label.show ();
            break;
        }
        default:
            message ("Unhandled UI state " + ui_state.to_string ());
            break;
        }
    }
}

