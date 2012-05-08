// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gdk;
using Gtk;

private abstract class Boxes.Machine: Boxes.CollectionItem, Boxes.IPropertiesProvider {
    public override Clutter.Actor actor { get { return machine_actor.actor; } }
    public Boxes.App app;
    public MachineActor machine_actor;
    public Boxes.CollectionSource source;
    public Boxes.DisplayConfig config;
    public Gdk.Pixbuf? pixbuf { get; set; }

    private ulong show_id;
    private ulong hide_id;
    private ulong disconnected_id;
    private ulong need_password_id;
    private ulong need_username_id;
    private ulong ui_state_id;
    private uint screenshot_id;
    public static const int SCREENSHOT_WIDTH = 180;
    public static const int SCREENSHOT_HEIGHT = 134;

    public enum MachineState {
        UNKNOWN,
        STOPPED,
        RUNNING,
        PAUSED
    }

    private MachineState _state;
    public MachineState state { get { return _state; }
        protected set {
            _state = value;
            debug ("State of '%s' changed to %s", name, state.to_string ());
        }
    }

    private Display? _display;
    public Display? display {
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
                Timeout.add (app.duration, () => {
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
                message (@"display $name disconnected");
                app.ui_state = Boxes.UIState.COLLECTION;
            });

            need_password_id = _display.notify["need-password"].connect (() => {
                machine_actor.set_password_needed (display.need_password);
            });

            need_username_id = _display.notify["need-username"].connect (() => {
                machine_actor.set_username_needed (display.need_username);
            });

            _display.password = machine_actor.get_password ();
        }
    }

    public Machine (Boxes.CollectionSource source, Boxes.App app, string name) {
        this.app = app;
        this.name = name;
        this.source = source;

        pixbuf = draw_fallback_vm ();
        machine_actor = new MachineActor (this);

        ui_state_id = app.notify["ui-state"].connect (() => {
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

    public virtual string get_screenshot_filename (string ext = "ppm") {
        return get_pkgcache (get_screenshot_prefix () + "-screenshot." + ext);
    }

    public virtual async bool take_screenshot () throws GLib.Error {
        return false;
    }

    public abstract List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page);

    public abstract string get_screenshot_prefix ();

    public abstract void connect_display ();
    public abstract void disconnect_display ();

    public bool is_running () {
        return state == MachineState.RUNNING;
    }

    public async void update_screenshot (int width = SCREENSHOT_WIDTH, int height = SCREENSHOT_HEIGHT) {
        try {
            yield take_screenshot ();
            pixbuf = new Gdk.Pixbuf.from_file (get_screenshot_filename ());
            machine_actor.set_screenshot (pixbuf); // high resolution
            pixbuf = draw_vm (pixbuf, width, height);
        } catch (GLib.Error error) {
            if (!(error is FileError.NOENT))
                warning ("%s: %s".printf (name, error.message));
        }

        if (pixbuf == null) {
            pixbuf = draw_fallback_vm (width, height);
            machine_actor.set_screenshot (pixbuf);
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
            context.scale (0.1875 / SCREENSHOT_WIDTH * width, 0.1875 / SCREENSHOT_HEIGHT * height);
            var grid = new Cairo.Pattern.for_surface (new Cairo.ImageSurface.from_png (get_pixmap ("boxes-grid.png")));
            grid.set_extend (Cairo.Extend.REPEAT);
            context.set_source_rgba (0, 0, 0, 1);
            context.set_operator (Cairo.Operator.OVER);
            context.mask (grid);
        }

        return Gdk.pixbuf_get_from_surface (surface, 0, 0, width, height);
    }

    private static Gdk.Pixbuf? default_fallback = null;
    private static Gdk.Pixbuf draw_fallback_vm (int width = SCREENSHOT_WIDTH,
                                                int height = SCREENSHOT_HEIGHT,
                                                bool force = false) {
        Gdk.Pixbuf pixbuf = null;

        if (width == SCREENSHOT_WIDTH && height == SCREENSHOT_HEIGHT && !force)
            if (default_fallback != null)
                return default_fallback;
            else
                default_fallback = draw_fallback_vm (width, height, true);

        try {
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
            var context = new Cairo.Context (surface);

            int size = (int) (height * 0.6);
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

    public bool deleted;
    public virtual void delete (bool by_user = true) {
        deleted = true;

        set_screenshot_enable (false);
        if (ui_state_id != 0) {
            app.disconnect (ui_state_id);
            ui_state_id = 0;
        }
    }

    public override void ui_state_changed () {
        machine_actor.ui_state = ui_state;
    }
}

private class Boxes.MachineActor: Boxes.UI {
    public override Clutter.Actor actor { get { return box; } }
    public Clutter.Box box;

    private Clutter.BindConstraint yconstraint;
    private GtkClutter.Texture screenshot;
    private GtkClutter.Actor gtk_vbox;
    private GtkClutter.Actor? display;
    private Gtk.Label label;
    private Gtk.VBox vbox; // and the vbox under it
    private Gtk.Entry password_entry;
    private Machine machine;
    private ulong height_id;

    static const int properties_y = 200;

    ~MachineActor() {
        machine.app.actor.disconnect (height_id);
        height_id = 0;
    }

    public MachineActor (Machine machine) {
        this.machine = machine;

        var layout = new Clutter.BoxLayout ();
        layout.vertical = true;
        layout.spacing = 10;
        box = new Clutter.Box (layout);

        screenshot = new GtkClutter.Texture ();
        screenshot.name = "screenshot";
        set_screenshot (machine.pixbuf);
        scale_screenshot ();
        actor_add (screenshot, box);
        screenshot.keep_aspect_ratio = true;

        vbox = new Gtk.VBox (false, 0);
        gtk_vbox = new GtkClutter.Actor.with_contents (vbox);

        gtk_vbox.get_widget ().get_style_context ().add_class ("boxes-bg");

        label = new Gtk.Label (machine.name);
        label.modify_fg (Gtk.StateType.NORMAL, get_color ("white"));
        machine.bind_property ("name", label, "label", BindingFlags.DEFAULT);
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
        actor.set_reactive (true);

        yconstraint = new Clutter.BindConstraint (machine.app.actor, BindCoordinate.Y,
                                                  machine.app.actor.height - properties_y);
        height_id = machine.app.actor.notify["height"].connect (() => {
            yconstraint.set_offset (machine.app.actor.height - properties_y);
        });

        yconstraint.enabled = false;
    }

    public void scale_screenshot (float scale = 1.5f) {
        screenshot.set_size (Machine.SCREENSHOT_WIDTH * scale,
                             Machine.SCREENSHOT_HEIGHT * scale);
    }

    public void set_screenshot (Gdk.Pixbuf pixbuf) {
        try {
            screenshot.set_from_pixbuf (pixbuf);
        } catch (GLib.Error err) {
            warning (err.message);
        }
    }

    public void set_password_needed (bool needed) {
        password_entry.visible = needed;
        password_entry.set_can_focus (needed);
        if (needed) {
            password_entry.grab_focus ();
            machine.display = null;
        }
    }

    public void set_username_needed (bool needed) {
        debug ("FIXME: Do something about fetching username when required?");
        if (needed)
            machine.display = null;
    }

    public string get_password () {
        return password_entry.text;
    }

    public override void ui_state_changed () {
        int window_width, window_height;
        int width, height;
        int x, y;

        yconstraint.enabled = false;
        machine.app.display_page.get_size (out width, out height);
        machine.app.window.get_size (out window_width, out window_height);
        x = window_width - width;
        y = window_height - height;

        switch (ui_state) {
        case UIState.CREDS:
            scale_screenshot (2.0f);
            break;

        case UIState.DISPLAY:
            if (previous_ui_state == UIState.CREDS) {
                password_entry.hide ();
                label.hide ();
                screenshot.animate (Clutter.AnimationMode.LINEAR, machine.app.duration,
                                    "width", (float) width,
                                    "height", (float) height);
                actor.animate (Clutter.AnimationMode.LINEAR, machine.app.duration,
                               "x", (float) x,
                               "y", (float) y);
            } else {
                if (display != null) {
                    // zoom in, back from properties
                    var anim = display.animate (Clutter.AnimationMode.LINEAR, machine.app.duration,
                                                "x", (float) x,
                                                "y", (float) y,
                                                "width", (float) width,
                                                "height", (float) height);
                    anim.completed.connect (() => {
                        actor_remove (display);
                        var widget = display.contents;
                        display.contents = null;
                        display = null;
                        // FIXME: enable grabs
                        machine.display.set_enable_inputs (widget, true);
                        machine.app.display_page.show_display (machine, widget);
                    });
                } else
                    machine.app.display_page.show ();
            }

            break;

        case UIState.COLLECTION:
            scale_screenshot ();
            password_entry.set_can_focus (false);
            password_entry.hide ();
            label.show ();
            break;

        case UIState.PROPERTIES:
            var widget = machine.app.display_page.remove_display ();
            machine.display.set_enable_inputs (widget, false);
            display = new GtkClutter.Actor.with_contents (widget);
            display.x = 0.0f;
            display.y = 0.0f;
            display.width = (float) width;
            display.height = (float) height;
            actor_add (display, machine.app.stage);
            display.add_constraint (yconstraint);

            display.animate (Clutter.AnimationMode.LINEAR, machine.app.duration,
                             "x", 10.0f,
                             "y", height - 200.0f,
                             "width", 180.0f,
                             "height", 130.0f).completed.connect (() => {
                                 yconstraint.enabled = true;
                             });

            break;

        default:
            break;
        }
    }
}
