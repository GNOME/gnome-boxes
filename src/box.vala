// This file is part of GNOME Boxes. License: LGPLv2
using Clutter;
using Gdk;
using Gtk;
using GVir;

private class Boxes.Box: Boxes.CollectionItem {
    public Boxes.App app;
    public BoxActor actor;
    public DomainState state {
        get {
            try {
                return domain.get_info ().state;
            } catch (GLib.Error error) {
                return DomainState.NONE;
            }
        }
    }

    private GVir.Domain _domain;
    public GVir.Domain domain {
        get { return _domain; }
        construct set {
            _domain = value;
        }
    }

    private Display display;

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

        app.state.completed.connect ( () => {
            if (app.state.state == "display") {
                if (app.selected_box != this)
                    return;

                try {
                    actor.show_display (display.get_display (0));
                } catch (Boxes.Error error) {
                    warning (error.message);
                }
            }
        });
    }

    public Clutter.Actor get_clutter_actor () {
        return actor.actor;
    }

    public async bool take_screenshot () throws GLib.Error {
        if (state != DomainState.RUNNING &&
            state != DomainState.PAUSED)
            return false;

        var stream = app.connection.get_stream (0);
        var file_name = get_screenshot_filename ();
        var file = File.new_for_path (file_name);
        var output_stream = yield file.replace_async (null, false, FileCreateFlags.REPLACE_DESTINATION);
        var input_stream = stream.get_input_stream ();
        domain.screenshot (stream, 0, 0);

        var buffer = new uint8[65535];
        ssize_t length = 0;
        do {
            length = yield input_stream.read_async (buffer);
            yield output_stream_write (output_stream, buffer[0:length]);
        } while (length > 0);

        return true;
    }

    public bool connect_display () {
        update_display ();

        if (display == null)
            return false;

        display.connect_it ();

        return true;
    }

    private string get_screenshot_filename (string ext = "ppm") {
        var uuid = domain.get_uuid ();

        return get_pkgcache (uuid + "-screenshot." + ext);
    }

    private async void update_screenshot () {
        Gdk.Pixbuf? pixbuf = null;

        try {
            yield take_screenshot ();
            pixbuf = new Gdk.Pixbuf.from_file (get_screenshot_filename ());
        } catch (GLib.Error error) {
            if (!(error is FileError.NOENT))
                warning (error.message);
        }

        if (pixbuf == null)
            pixbuf = draw_fallback_vm (128, 96);

        try {
            actor.set_screenshot (pixbuf);
        } catch (GLib.Error err) {
            warning (err.message);
        }
    }

    private static Gdk.Pixbuf draw_fallback_vm (int width, int height) {
        Gdk.Pixbuf pixbuf = null;

        try {
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
            var context = new Cairo.Context (surface);

            var pattern = new Cairo.Pattern.linear (0, 0, 0, height);
            pattern.add_color_stop_rgb (0, 0.260, 0.260, 0.260);
            pattern.add_color_stop_rgb (1, 0.220, 0.220, 0.220);

            context.set_source (pattern);
            context.paint ();

            int size = (int) (height * 0.5);
            var icon_info = IconTheme.get_default ().lookup_icon ("computer-symbolic", size,
                                                                  IconLookupFlags.GENERIC_FALLBACK);
            Gdk.cairo_set_source_pixbuf (context, icon_info.load_icon (),
                                         (width - size) / 2, (height - size) / 2);
            context.rectangle ((width - size) / 2, (height - size) / 2, size, size);
            context.fill ();
            pixbuf = Gdk.pixbuf_get_from_surface (surface, 0, 0, width, height);
        } catch {
        }

        if (pixbuf != null)
            return pixbuf;

        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
        return Gdk.pixbuf_get_from_surface (surface, 0, 0, width, height);
    }

    private void update_display () {
        string type, gport, socket, ghost;

        try {
            var xmldoc = domain.get_config (0).doc;
            type = extract_xpath (xmldoc, "string(/domain/devices/graphics/@type)", true);
            gport = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@port)");
            socket = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@socket)");
            ghost = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@listen)");
        } catch (GLib.Error error) {
            warning (error.message);

            return;
        }

        if (type == "spice") {
            display = new SpiceDisplay (ghost, int.parse (gport));
        } else {
            warning ("unsupported display of type " + type);

            return;
        }

        display.show.connect ((id) => {
            app.ui_state = Boxes.UIState.DISPLAY;
        });

        display.disconnected.connect (() => {
            app.ui_state = Boxes.UIState.COLLECTION;
        });
    }
}

private class Boxes.BoxActor: Boxes.UI {
    public Clutter.Box actor;

    private GtkClutter.Texture screenshot;
    private GtkClutter.Actor gtkactor;
    private Gtk.Label label;
    private Gtk.VBox vbox; // and the vbox under it
    private Gtk.Entry entry;
    private Gtk.Widget? display;
    private Box box;

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
        entry.set_placeholder_text (_("Password")); // TODO: i18n stupid vala...
        vbox.add (entry);

        vbox.show_all ();
        entry.hide ();

        actor_add (gtkactor, cbox);

        actor = cbox;
    }

    public void scale_screenshot (float scale = 1.5f) {
        screenshot.set_size (128 * scale, 96 * scale);
    }

    public void set_screenshot (Gdk.Pixbuf pixbuf) throws GLib.Error {
        screenshot.set_from_pixbuf (pixbuf);
    }

    public void show_display (Gtk.Widget display) {
        if (this.display != null) {
            warning ("This box actor already contains a display");
            return;
        }

        actor_remove (screenshot);

        this.display = display;
        vbox.add (display);

        display.show ();
        display.grab_focus ();
    }

    public void hide_display () {
        if (display == null)
            return;

        vbox.remove (display);
        display = null;

        actor.pack_at (screenshot, 0);
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.CREDS:
            scale_screenshot (2.0f);
            entry.show ();
            // actor.entry.set_sensitive (false); FIXME: depending on spice-gtk conn. results
            entry.set_can_focus (true);
            entry.grab_focus ();

            break;

        case UIState.DISPLAY: {
            int width, height;

            entry.hide ();
            label.hide ();
            box.app.window.get_size (out width, out height);
            screenshot.animate (Clutter.AnimationMode.LINEAR, Boxes.App.duration,
                                "width", (float) width,
                                "height", (float) height);
            actor.animate (Clutter.AnimationMode.LINEAR, Boxes.App.duration,
                           "x", 0.0f,
                           "y", 0.0f);

            break;
        }

        case UIState.COLLECTION:
            hide_display ();
            scale_screenshot ();
            entry.set_can_focus (false);
            entry.hide ();
            label.show ();

            break;

        default:
            message ("Unhandled UI state " + ui_state.to_string ());

            break;
        }
    }
}

