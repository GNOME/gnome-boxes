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
    public GVir.Connection connection;
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
    private ulong need_password_id;
    private uint screenshot_id;

    private Display? _display;
    private Display? display {
        get { return _display; }
        set {
            if (_display != null) {
                _display.disconnect (show_id);
                _display.disconnect (disconnected_id);
                _display.disconnect (need_password_id);
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

            need_password_id = display.notify["need-password"].connect (() => {
                machine_actor.set_password_needed (display.need_password);
            });

            display.password = machine_actor.get_password ();
        }
    }

    public Machine (Boxes.App app, GVir.Connection connection, GVir.Domain domain) {
        this.app = app;
        this.connection = connection;
        this.domain = domain;

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
                GLib.Source.remove (screenshot_id);
            screenshot_id = 0;
        }
    }

    public async bool take_screenshot () throws GLib.Error {
        if (state != DomainState.RUNNING &&
            state != DomainState.PAUSED)
            return false;

        var stream = connection.get_stream (0);
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

    private ulong started_id;
    private bool _connect_display;
    public bool connect_display {
        get { return _connect_display; }
        set {
            if (_connect_display == value)
                return;

            if (value && state != DomainState.RUNNING) {
                if (started_id != 0)
                    return;

                if (state == DomainState.PAUSED) {
                    started_id = domain.resumed.connect (() => {
                        domain.disconnect (started_id);
                        started_id = 0;
                        connect_display = true;
                    });
                    try {
                        domain.resume ();
                    } catch (GLib.Error e) {
                        warning (e.message);
                    }
                } else if (state != DomainState.RUNNING) {
                    started_id = domain.started.connect (() => {
                        domain.disconnect (started_id);
                        started_id = 0;
                        connect_display = true;
                    });
                    try {
                        domain.start (0);
                    } catch (GLib.Error e) {
                        warning (e.message);
                    }
                }
            }

            _connect_display = value;
            update_display ();
        }
    }

    private string get_screenshot_filename (string ext = "ppm") {
        var uuid = domain.get_uuid ();

        return get_pkgcache (uuid + "-screenshot." + ext);
    }

    public async void update_screenshot (int width = 128, int height = 96) {
        Gdk.Pixbuf? pixbuf = null;

        try {
            yield take_screenshot ();
            pixbuf = new Gdk.Pixbuf.from_file (get_screenshot_filename ());
        } catch (GLib.Error error) {
            if (!(error is FileError.NOENT))
                warning ("%s: %s".printf (name, error.message));
        }

        if (pixbuf == null)
            pixbuf = draw_fallback_vm (width, height);
        else
            pixbuf = draw_vm (pixbuf, pixbuf.get_width (), pixbuf.get_height ());

        try {
            machine_actor.set_screenshot (pixbuf);
        } catch (GLib.Error err) {
            warning (err.message);
        }
    }

    private Gdk.Pixbuf draw_vm (Gdk.Pixbuf pixbuf, int width, int height) {
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
        var context = new Cairo.Context (surface);

        var pw = (double)pixbuf.get_width ();
        var ph = (double)pixbuf.get_height ();
        var sw = width / pw;
        var sh = height / ph;
        var x = 0.0;
        var y = 0.0;

        if (pw > ph) {
            y = (height - (ph * sw)) / 2;
            sh = sw;
        }

        context.rectangle (x, y, width - x * 2, height - y * 2);
        context.clip ();

        context.scale (sw, sh);
        Gdk.cairo_set_source_pixbuf (context, pixbuf, x / sw, y / sh);
        context.get_source ().set_filter (Cairo.Filter.BEST); // FIXME: cairo scaling is crap
        context.paint ();

        if (state != DomainState.RUNNING) {
            context.set_source_rgba (1, 1, 1, 1);
            context.set_operator (Cairo.Operator.HSL_SATURATION);
            context.paint ();

            context.identity_matrix ();
            context.scale (0.1875 / 128 * width, 0.1875 / 96 * height);
            var grid = new Cairo.Pattern.for_surface (new Cairo.ImageSurface.from_png (get_pixmap ("boxes-grid.png")));
            grid.set_extend (Cairo.Extend.REPEAT);
            context.set_source_rgba (1, 1, 1, 1);
            context.set_operator (Cairo.Operator.OVER);
            context.mask (grid);
        }

        return Gdk.pixbuf_get_from_surface (surface, 0, 0, width, height);
    }

    private static Gdk.Pixbuf draw_fallback_vm (int width, int height) {
        Gdk.Pixbuf pixbuf = null;

        try {
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
            var context = new Cairo.Context (surface);

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
            if (display != null)
                display.disconnect_it ();
            display = new SpiceDisplay (ghost, int.parse (gport));
        } else {
            warning ("unsupported display of type " + type);

            return;
        }

        if (connect_display)
            display.connect_it ();
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
    private Gtk.Label label;
    private Gtk.VBox vbox; // and the vbox under it
    private Gtk.Entry password_entry;
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
        password_entry = new Gtk.Entry ();
        password_entry.set_visibility (false);
        password_entry.set_placeholder_text (_("Password"));
        set_password_needed (false);
        password_entry.key_press_event.connect ((event) => {
            if (event.keyval == Gdk.Key.KP_Enter ||
                event.keyval == Gdk.Key.ISO_Enter ||
                event.keyval == Gdk.Key.Return) {
                machine.connect_display = true;
                return true;
            }

            return false;
        });
        vbox.add (password_entry);

        vbox.show_all ();
        password_entry.hide ();

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

        // FIXME: there is flickering if we show it without delay
        // where does this rendering delay come from?
        Timeout.add (Boxes.App.duration, () => {
            machine.app.display_page.show_display (display);
            display.grab_focus ();
            return false;
        });
    }

    public void hide_display () {
        machine.app.display_page.remove_display ();
        display = null;
    }

    public void set_password_needed (bool needed) {
        password_entry.set_sensitive (needed);
        password_entry.set_can_focus (needed);
        if (needed)
            password_entry.grab_focus ();
    }

    public string get_password () {
        return password_entry.text;
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.CREDS:
            scale_screenshot (2.0f);
            password_entry.show ();
            break;

        case UIState.DISPLAY: {
            int width, height;

            password_entry.hide ();
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
            password_entry.set_can_focus (false);
            password_entry.hide ();
            label.show ();

            break;

        default:
            message ("Unhandled UI state " + ui_state.to_string ());

            break;
        }
    }
}
