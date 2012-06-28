// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gdk;
using Gtk;

private abstract class Boxes.Machine: Boxes.CollectionItem, Boxes.IPropertiesProvider {
    public override Clutter.Actor actor { get { return machine_actor.actor; } }
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
    private static Cairo.Surface grid_surface;
    private bool updating_screenshot;

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
                App.app.ui_state = Boxes.UIState.DISPLAY;
                Timeout.add (App.app.duration, () => {
                    if  (App.app.ui_state != Boxes.UIState.DISPLAY)
                          return false;
                    try {
                        var widget = display.get_display (0);
                        App.app.display_page.show_display (display, widget);
                        widget.grab_focus ();
                    } catch (Boxes.Error error) {
                        warning (error.message);
                    }

                    return false;
                });
            });

            hide_id = _display.hide.connect ((id) => {
                App.app.display_page.remove_display ();
            });

            disconnected_id = _display.disconnected.connect (() => {
                message (@"display $name disconnected");
                App.app.ui_state = Boxes.UIState.COLLECTION;
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

    static construct {
        grid_surface = new Cairo.ImageSurface.from_png (get_pixmap ("boxes-grid.png"));
    }

    public Machine (Boxes.CollectionSource source, string name) {
        this.name = name;
        this.source = source;

        pixbuf = draw_fallback_vm ();
        machine_actor = new MachineActor (this);

        ui_state_id = App.app.notify["ui-state"].connect (() => {
            if (App.app.ui_state == UIState.DISPLAY)
                set_screenshot_enable (false);
            else
                set_screenshot_enable (true);
        });

    }

    public void load_screenshot () {
        try {
            var screenshot = new Gdk.Pixbuf.from_file (get_screenshot_filename ());
            set_screenshot (screenshot, false);
        } catch (GLib.Error error) {
        }
    }

    public void set_screenshot_enable (bool enable) {
        if (enable) {
            if (screenshot_id != 0)
                return;
            update_screenshot.begin (false, true);
            var interval = App.app.settings.get_int ("screenshot-interval");
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

    public string get_screenshot_filename () {
        return get_user_pkgcache (get_screenshot_prefix () + "-screenshot.png");
    }

    public async virtual Gdk.Pixbuf? take_screenshot () throws GLib.Error {
        return null;
    }

    public abstract List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page);

    public abstract string get_screenshot_prefix ();

    public abstract void connect_display ();

    public virtual void disconnect_display () {
        if (display == null)
            return;

        try {
            var pixbuf = display.get_pixbuf (0);
            if (pixbuf != null)
                set_screenshot (pixbuf, true);
        } catch (GLib.Error error) {
            warning (error.message);
        }

        App.app.display_page.remove_display ();
        display.disconnect_it ();
        display = null;
    }

    public bool is_running () {
        return state == MachineState.RUNNING;
    }

    public void set_screenshot (Gdk.Pixbuf? large_screenshot, bool save) {
        if (large_screenshot != null) {
            var pw = large_screenshot.get_width ();
            var ph = large_screenshot.get_height ();
            var s = double.min ((double)SCREENSHOT_WIDTH / pw, (double)SCREENSHOT_HEIGHT / ph);
            int w = (int) (pw * s);
            int h = (int) (ph * s);

            var small_screenshot = new Gdk.Pixbuf (Gdk.Colorspace.RGB, large_screenshot.has_alpha, 8, w, h);
            large_screenshot.scale (small_screenshot, 0, 0, w, h, 0, 0, s, s, Gdk.InterpType.HYPER);

            pixbuf = draw_vm (small_screenshot, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
            machine_actor.set_screenshot (large_screenshot); // high resolution

            if (save) {
                try {
                    pixbuf.save (get_screenshot_filename (), "png");
                } catch (GLib.Error error) {
                }
            }
        } else if (pixbuf == null) {
            pixbuf = draw_fallback_vm (SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
            machine_actor.set_screenshot (pixbuf);
        }
    }

    int screenshot_counter;
    public async void update_screenshot (bool force_save = false, bool first_check = false) {
        if (updating_screenshot)
            return;

        updating_screenshot = true;

        Gdk.Pixbuf? large_screenshot = null;
        try {
            large_screenshot = yield take_screenshot ();
            // There is some kind of bug in libvirt, so the first time we
            // take a screenshot after displaying the box we get the old
            // screenshot from before connecting to the box
            if (first_check)
                large_screenshot = yield take_screenshot ();
        } catch (GLib.Error error) {
        }
        // Save the screenshot first time and every 60 sec
        set_screenshot (large_screenshot, force_save || screenshot_counter++ % 12 == 0);

        updating_screenshot = false;
    }

    private Gdk.Pixbuf draw_vm (Gdk.Pixbuf pixbuf, int width, int height) {
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
        var context = new Cairo.Context (surface);

        var pw = pixbuf.get_width ();
        var ph = pixbuf.get_height ();
        var x = (width - pw) / 2;
        var y = (height - ph) / 2;

        context.rectangle (x, y, pw, ph);
        context.clip ();

        Gdk.cairo_set_source_pixbuf (context, pixbuf, x, y);
        context.set_operator (Cairo.Operator.SOURCE);
        context.paint ();

        if (!is_running ()) {
            context.set_source_rgba (1, 1, 1, 1);
            context.set_operator (Cairo.Operator.HSL_SATURATION);
            context.paint ();

            context.identity_matrix ();
            context.scale (0.1875 / SCREENSHOT_WIDTH * width, 0.1875 / SCREENSHOT_HEIGHT * height);
            var grid = new Cairo.Pattern.for_surface (grid_surface);
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
            App.app.disconnect (ui_state_id);
            ui_state_id = 0;
        }
    }

    public override void ui_state_changed () {
        machine_actor.ui_state = ui_state;
    }
}

private class Boxes.MachineActor: Boxes.UI {
    public override Clutter.Actor actor { get { return _actor; } }
    public Clutter.Actor _actor;

    private GtkClutter.Texture screenshot;
    private GtkClutter.Actor gtk_vbox;
    private GtkClutter.Actor? display;
    private Gtk.Label label;
    private Gtk.VBox vbox; // and the vbox under it
    private Gtk.Entry password_entry;
    private Machine machine;
    ulong track_screenshot_id = 0;

    ~MachineActor() {
        if (track_screenshot_id != 0)
            App.app.properties.screenshot_placeholder.disconnect (track_screenshot_id);
    }

    public MachineActor (Machine machine) {
        this.machine = machine;

        var layout = new Clutter.BoxLayout ();
        layout.vertical = true;
        layout.spacing = 10;
        _actor = new Clutter.Actor ();
        _actor.set_layout_manager (layout);

        screenshot = new GtkClutter.Texture ();
        screenshot.name = "screenshot";
        set_screenshot (machine.pixbuf);
        _actor.min_width = _actor.natural_width = Machine.SCREENSHOT_WIDTH;

        screenshot.keep_aspect_ratio = true;
        _actor.add (screenshot);

        vbox = new Gtk.VBox (false, 0);
        gtk_vbox = new GtkClutter.Actor.with_contents (vbox);
        // Ensure we have enough space to fit everything without changing
        // size, as that causes weird re-animations
        gtk_vbox.height = 80;

        gtk_vbox.get_widget ().get_style_context ().add_class ("boxes-bg");

        label = new Gtk.Label (machine.title);
        label.modify_fg (Gtk.StateType.NORMAL, get_color ("white"));
        machine.bind_property ("title", label, "label", BindingFlags.DEFAULT);
        vbox.add (label);
        vbox.set_valign (Gtk.Align.START);
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

        _actor.add (gtk_vbox);
        _actor.set_reactive (true);
    }

    public void set_screenshot (Gdk.Pixbuf pixbuf) {
        try {
            screenshot.set_from_pixbuf (pixbuf);
        } catch (GLib.Error err) {
            warning (err.message);
        }
    }

    public void set_password_needed (bool needed) {
        _actor.queue_relayout ();
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

        App.app.display_page.get_size (out width, out height);
        App.app.window.get_size (out window_width, out window_height);
        x = window_width - width;
        y = window_height - height;

        switch (ui_state) {
        case UIState.CREDS:
            gtk_vbox.show ();
            break;

        case UIState.DISPLAY:
            gtk_vbox.hide ();
            if (previous_ui_state == UIState.CREDS) {
                App.app.overlay_bin.set_alignment (actor,
                                                   Clutter.BinAlignment.FILL,
                                                   Clutter.BinAlignment.FILL);
            } else {
                if (display != null) {
                    // zoom in, back from properties

                    App.app.properties.screenshot_placeholder.disconnect (track_screenshot_id);
                    track_screenshot_id = 0;

                    display.set_easing_duration (App.app.duration);
                    App.app.overlay_bin.set_alignment (display,
                                                       Clutter.BinAlignment.FILL,
                                                       Clutter.BinAlignment.FILL);

                    display.transitions_completed.connect (() => {
                        var widget = display.contents;
                        display.contents = null;
                        display.destroy ();
                        display = null;
                        // FIXME: enable grabs
                        machine.display.set_enable_inputs (widget, true);
                        App.app.display_page.show_display (machine.display, widget);
                    });
                } else
                    App.app.display_page.show ();
            }
            break;

        case UIState.COLLECTION:
            password_entry.set_can_focus (false);
            password_entry.hide ();
            label.show ();
            break;

        case UIState.PROPERTIES:
            var widget = App.app.display_page.remove_display ();
            machine.display.set_enable_inputs (widget, false);
            display = new GtkClutter.Actor.with_contents (widget);
            display.name = "properties-thumbnail";
            display.set_easing_mode (Clutter.AnimationMode.LINEAR);
            App.app.overlay_bin.add (display,
                                     Clutter.BinAlignment.FILL,
                                     Clutter.BinAlignment.FILL);

            Clutter.ActorBox box = { 0, 0,  width, height};
            display.allocate (box, 0);
            display.show ();

            // Temporarily hide toolbar in fullscreen so that the the animation
            // actor doesn't get pushed down before zooming to the sidebar
            if (App.app.fullscreen)
                App.app.topbar.actor.hide ();

            bool completed_zoom = false;
            ulong completed_id = 0;
            completed_id = display.transitions_completed.connect (() => {
                display.disconnect (completed_id);
                completed_zoom = true;
            });

            track_screenshot_id = App.app.properties.screenshot_placeholder.size_allocate.connect ( (alloc) => {
                Idle.add_full (Priority.HIGH, () => {
                    App.app.topbar.actor.show ();
                    App.app.overlay_bin.set_alignment (display,
                                                       Clutter.BinAlignment.FIXED,
                                                       Clutter.BinAlignment.FIXED);

                    // Don't animate x/y/width/height
                    display.set_easing_duration (0);
                    display.x = alloc.x;
                    display.y = alloc.y;
                    display.width = alloc.width;
                    display.height = alloc.height;

                    if (!completed_zoom)
                        display.set_easing_duration (App.app.duration);

                    return false;
                });
            });

            break;

        default:
            break;
        }
    }
}
