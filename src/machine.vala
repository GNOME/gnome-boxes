// This file is part of GNOME Boxes. License: LGPLv2
using Clutter;
using Gdk;
using Gtk;
using GVir;

private class Boxes.Machine: Boxes.CollectionItem {
    public override Clutter.Actor actor { get { return machine_actor.actor; } }
    public Boxes.App app;
    public MachineActor machine_actor;
    public GVir.Domain domain;
    public DomainState state {
        get {
            try {
                return domain.get_info ().state;
            } catch (GLib.Error error) {
                return DomainState.NONE;
            }
        }
    }

    private ulong show_id;
    private ulong disconnected_id;
    private uint screenshot_id;

    private Display? _display;
    private Display? display {
        get { return _display; }
        set {
            if (_display != null) {
                _display.disconnect (show_id);
                _display.disconnect (disconnected_id);
            }

            _display = value;

            show_id = _display.show.connect ((id) => {
                app.ui_state = Boxes.UIState.DISPLAY;
                try {
                    machine_actor.show_display (display.get_display (0));
                } catch (Boxes.Error error) {
                    warning (error.message);
                }
            });

            disconnected_id = _display.disconnected.connect (() => {
                app.ui_state = Boxes.UIState.COLLECTION;
            });
        }
    }

    public Machine (Boxes.App app, GVir.Domain domain) {
        this.domain = domain;
        this.app = app;

        name = domain.get_name ();
        machine_actor = new MachineActor (this);

        set_screenshot_enable (true);
        app.notify["ui-state"].connect (() => {
            if (app.ui_state == UIState.DISPLAY)
                set_screenshot_enable (false);
            else
                set_screenshot_enable (true);
        });
    }

    public void set_screenshot_enable (bool enable) {
        if (enable) {
            if (screenshot_id != 0)
                return;
            update_screenshot.begin ();
            screenshot_id = Timeout.add_seconds (5, () => {
                update_screenshot.begin ();
                return true;
            });
        } else {
            if (screenshot_id != 0)
                Source.remove (screenshot_id);
            screenshot_id = 0;
        }
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
            machine_actor.set_screenshot (pixbuf);
        } catch (GLib.Error err) {
            warning (err.message);
        }
    }

    private static Gdk.Pixbuf draw_fallback_vm (int width, int height) {
        Gdk.Pixbuf pixbuf = null;

        try {
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
            var context = new Cairo.Context (surface);

            // make it take color from theme
            // var pattern = new Cairo.Pattern.linear (0, 0, 0, height);
            // pattern.add_color_stop_rgb (0, 0.260, 0.260, 0.260);
            // pattern.add_color_stop_rgb (1, 0.220, 0.220, 0.220);
            // context.set_source (pattern);
            // context.paint ();

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
    }

    public override void ui_state_changed () {
        machine_actor.ui_state = ui_state;
    }
}

private class Boxes.MachineActor: Boxes.UI {
    public override Clutter.Actor actor { get { return box; } }
    public Clutter.Box box;

    private GtkClutter.Texture screenshot;
    public GtkClutter.Actor gtk_vbox;
    public GtkClutter.Actor gtk_display;
    private Gtk.Label label;
    private Gtk.VBox vbox; // and the vbox under it
    private Gtk.Entry entry;
    private Gtk.Widget? display;
    private Machine machine;

    public MachineActor (Machine machine) {
        this.machine = machine;

        var layout = new Clutter.BoxLayout ();
        layout.vertical = true;
        box = new Clutter.Box (layout);

        screenshot = new GtkClutter.Texture ();
        screenshot.name = "screenshot";

        scale_screenshot ();
        actor_add (screenshot, box);
        screenshot.keep_aspect_ratio = true;

        vbox = new Gtk.VBox (false, 0);
        gtk_vbox = new GtkClutter.Actor.with_contents (vbox);

        gtk_vbox.get_widget ().get_style_context ().add_class ("boxes-bg");

        label = new Gtk.Label (machine.name);
        vbox.add (label);
        entry = new Gtk.Entry ();
        entry.set_visibility (false);
        entry.set_placeholder_text (_("Password"));
        vbox.add (entry);

        vbox.show_all ();
        entry.hide ();

        actor_add (gtk_vbox, box);
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

        /* before display was in the vbox, but there are scaling issues, so now on stage */
        this.display = display;
        gtk_display = new GtkClutter.Actor.with_contents (display);
        gtk_display.add_constraint_with_name ("display-fs", new Clutter.BindConstraint (machine.app.stage, BindCoordinate.SIZE, 0));
        display.show ();

        // FIXME: there is flickering if we show it without delay
        // where does this rendering delay come from?
        Timeout.add (Boxes.App.duration, () => {
            machine.app.stage.add (gtk_display);
            gtk_display.grab_key_focus ();
            display.grab_focus ();
            return false;
        });
    }

    public void hide_display () {
        if (display == null)
            return;

        actor_remove (gtk_display);
        display = null;
        gtk_display = null;
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
            machine.app.window.get_size (out width, out height);
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
