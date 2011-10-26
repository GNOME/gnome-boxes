// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gdk;
using Gtk;
using GVir;

private abstract class Boxes.Machine: Boxes.CollectionItem {
    public override Clutter.Actor actor { get { return machine_actor.actor; } }
    public Boxes.App app;
    public MachineActor machine_actor;
    public Boxes.CollectionSource source;

    private ulong show_id;
    private ulong hide_id;
    private ulong disconnected_id;
    private ulong need_password_id;
    private ulong need_username_id;
    private uint screenshot_id;

    private Display? _display;
    protected Display? display {
        get { return _display; }
        set {
            if (_display != null) {
                _display.disconnect (show_id);
                show_id = 0;
                _display.disconnect (hide_id);
                hide_id = 0;
                _display.disconnect (disconnected_id);
                disconnected_id = 0;
                _display.disconnect (need_password_id);
                need_password_id = 0;
                _display.disconnect (need_username_id);
                need_username_id = 0;
            }

            _display = value;
            if (_display == null)
                return;

            show_id = _display.show.connect ((id) => {
                app.ui_state = Boxes.UIState.DISPLAY;
                Timeout.add (Boxes.App.duration, () => {
                    try {
                        var widget = display.get_display (0);
                        app.display_page.show_display (this, widget);
                        widget.grab_focus ();
                    } catch (Boxes.Error error) {
                        warning (error.message);
                    }

                    return false;
                });
            });

            hide_id = _display.hide.connect ((id) => {
                app.display_page.remove_display ();
            });

            disconnected_id = _display.disconnected.connect (() => {
                app.ui_state = Boxes.UIState.COLLECTION;
            });

            need_password_id = _display.notify["need-password"].connect (() => {
                machine_actor.set_password_needed (display.need_password);
            });

            need_username_id = _display.notify["need-username"].connect (() => {
                machine_actor.set_username_needed (display.need_username);
            });

            _display.password = machine_actor.get_password ();

            if (_connect_display)
                display.connect_it ();
        }
    }

    public Machine (Boxes.CollectionSource source, Boxes.App app, string name) {
        this.app = app;
        this.name = name;
        this.source = source;

        machine_actor = new MachineActor (this);

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

    public string get_screenshot_filename (string ext = "ppm") {
        return get_pkgcache (get_screenshot_prefix () + "-screenshot." + ext);
    }

    public virtual async bool take_screenshot () throws GLib.Error {
        return false;
    }

    public abstract bool is_running ();
    public abstract string get_screenshot_prefix ();

    protected bool _connect_display;
    public abstract void connect_display ();
    public abstract void disconnect_display ();

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

        if (!is_running ()) {
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

    public override void ui_state_changed () {
        machine_actor.ui_state = ui_state;
    }
}

private class Boxes.LibvirtMachine: Boxes.Machine {
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

    public override void disconnect_display () {
        if (_connect_display == false)
            return;

        _connect_display = false;
        app.display_page.remove_display ();
        update_display ();
    }

    private ulong started_id;
    public override void connect_display () {
        if (_connect_display == true)
            return;

        if (state != DomainState.RUNNING) {
            if (started_id != 0)
                return;

            if (state == DomainState.PAUSED) {
                started_id = domain.resumed.connect (() => {
                    domain.disconnect (started_id);
                    started_id = 0;
                    connect_display ();
                });
                try {
                    domain.resume ();
                } catch (GLib.Error error) {
                    warning (error.message);
                }
            } else if (state != DomainState.RUNNING) {
                started_id = domain.started.connect (() => {
                    domain.disconnect (started_id);
                    started_id = 0;
                    connect_display ();
                });
                try {
                    domain.start (0);
                } catch (GLib.Error error) {
                    warning (error.message);
                }
            }
        }

        _connect_display = true;
        update_display ();
    }

    public LibvirtMachine (CollectionSource source, Boxes.App app,
                           GVir.Connection connection, GVir.Domain domain) {
        base (source, app, domain.get_name ());

        this.connection = connection;
        this.domain = domain;

        set_screenshot_enable (true);
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

        if (display != null)
            display.disconnect_it ();

        switch (type) {
        case "spice":
            display = new SpiceDisplay (ghost, int.parse (gport));
            break;

        case "vnc":
            display = new VncDisplay (ghost, int.parse (gport));
            break;

        default:
            warning ("unsupported display of type " + type);
            break;
        }
    }

    public override string get_screenshot_prefix () {
        return domain.get_uuid ();
    }

    public override bool is_running () {
        return state == DomainState.RUNNING;
    }

    public override async bool take_screenshot () throws GLib.Error {
        if (state != DomainState.RUNNING &&
            state != DomainState.PAUSED)
            return true;

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
}

private class Boxes.SpiceMachine: Boxes.Machine {

    public SpiceMachine (CollectionSource source, Boxes.App app) {
        base (source, app, source.name);

        update_screenshot.begin ();
    }

    public override void connect_display () {
        if (_connect_display == true)
            return;

        display = new SpiceDisplay.with_uri (source.uri);
        display.connect_it ();
    }

    public override void disconnect_display () {
        _connect_display = false;

        app.display_page.remove_display ();

        if (display != null) {
            display.disconnect_it ();
            display = null;
        }
    }

    public override string get_screenshot_prefix () {
        return source.filename;
    }

    public override bool is_running () {
        // assume the remote is running for now
        return true;
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
                machine.connect_display ();

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

    public void set_password_needed (bool needed) {
        password_entry.set_sensitive (needed);
        password_entry.set_can_focus (needed);
        if (needed)
            password_entry.grab_focus ();
    }

    public void set_username_needed (bool needed) {
        debug ("fixme");
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

        case UIState.DISPLAY:
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

        case UIState.COLLECTION:
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
