// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gdk;
using Gtk;

private abstract class Boxes.Machine: Boxes.CollectionItem, Boxes.IProperties {
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
            var interval = app.settings.get_int ("screenshot-interval");
            screenshot_id = Timeout.add_seconds (interval, () => {
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

    public abstract List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page);

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
        } catch (GLib.Error error) {
            warning (error.message);
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
            if (previous_ui_state == UIState.CREDS) {
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
            } else
                machine.app.display_page.show ();

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
