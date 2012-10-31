// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gdk;
using Gtk;

private abstract class Boxes.Machine: Boxes.CollectionItem, Boxes.IPropertiesProvider {
    public override Clutter.Actor actor { get { return machine_actor.actor; } }
    public MachineActor machine_actor;
    public Boxes.CollectionSource source;
    public Boxes.BoxConfig config;
    public Gdk.Pixbuf? pixbuf { get; set; }
    public bool stay_on_display;
    public string? info { get; set; }
    public string? status { get; set; }
    public bool suspend_at_exit;

    private ulong show_id;
    private ulong hide_id;
    private uint show_timeout_id;
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
        FORCE_STOPPED,
        RUNNING,
        PAUSED,
        SAVED,
        SLEEPING
    }

    // The current screenshot without running status applied
    private Gdk.Pixbuf? orig_pixbuf;

    private MachineState _state;
    public MachineState state { get { return _state; }
        protected set {
            _state = value;
            debug ("State of '%s' changed to %s", name, state.to_string ());
            if (value == MachineState.STOPPED || value == MachineState.FORCE_STOPPED)
                set_screenshot (null, false);
            else {
                // Update existing screenshot based on machine status
                if (orig_pixbuf != null)
                    pixbuf = draw_vm (orig_pixbuf, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
            }
        }
    }

    private void show_display () {
        Gtk.Widget widget;

        widget = display.get_display (0);

        switch (App.app.ui_state) {
        case Boxes.UIState.DISPLAY:
            App.app.display_page.show_display (display, widget);
            widget.grab_focus ();
            break;

        case Boxes.UIState.PROPERTIES:
            machine_actor.update_thumbnail (widget, false);
            break;
        }
    }

    private Display? _display;
    public Display? display {
        get { return _display; }
        set {
            if (_display != null) {
                _display.disconnect (show_id);
                show_id = 0;
                if (show_timeout_id != 0)
                    GLib.Source.remove (show_timeout_id);
                show_timeout_id = 0;
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

            // Translators: The %s will be expanded with the name of the vm
            status = _("Connecting to %s").printf (name);

            show_id = _display.show.connect ((id) => {
                switch (App.app.ui_state) {
                case Boxes.UIState.CREDS:
                    App.app.ui_state = Boxes.UIState.DISPLAY;
                    show_timeout_id = Timeout.add (App.app.duration, () => {
                        show_timeout_id = 0;
                        show_display ();
                        return false;
                     });
                    break;

                case Boxes.UIState.DISPLAY:
                case Boxes.UIState.PROPERTIES:
                    show_display ();
                    break;
                }
            });

            hide_id = _display.hide.connect ((id) => {
                App.app.display_page.remove_display ();
            });

            disconnected_id = _display.disconnected.connect (() => {
                message (@"display $name disconnected");
                if (!stay_on_display)
                    App.app.ui_state = Boxes.UIState.COLLECTION;
            });

            need_password_id = _display.notify["need-password"].connect (() => {
                // Translators: The %s will be expanded with the name of the vm
                status = _("Enter password for %s").printf (name);
                machine_actor.set_password_needed (display.need_password);
            });

            need_username_id = _display.notify["need-username"].connect (() => {
                machine_actor.set_username_needed (display.need_username);
            });

            _display.password = machine_actor.get_password ();
        }
    }

    static construct {
        grid_surface = new Cairo.ImageSurface (Cairo.Format.A8, 2, 2);
        var cr = new Cairo.Context (grid_surface);
        cr.set_source_rgba (0, 0, 0, 0);
        cr.paint ();

        cr.set_source_rgba (1, 1, 1, 1);
        cr.set_operator (Cairo.Operator.SOURCE);
        cr.rectangle (0, 0, 1, 1);
        cr.fill ();
        cr.rectangle (1, 1, 1, 1);
        cr.fill ();
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

    private string get_screenshot_filename () throws Boxes.Error {
        if (config.uuid == null)
            throw new Boxes.Error.INVALID ("no uuid, cannot build screenshot filename");

        return Boxes.get_screenshot_filename (config.uuid);
    }

    public virtual async void save () throws GLib.Error {
    }

    public virtual async Gdk.Pixbuf? take_screenshot () throws GLib.Error {
        return null;
    }

    public abstract List<Boxes.Property> get_properties (Boxes.PropertiesPage page);

    public abstract async void connect_display () throws GLib.Error;

    public virtual void disconnect_display () {
        if (display == null)
            return;

        if (state != MachineState.STOPPED && state != MachineState.FORCE_STOPPED) {
            try {
                var pixbuf = display.get_pixbuf (0);
                if (pixbuf != null)
                    set_screenshot (pixbuf, true);
            } catch (GLib.Error error) {
                warning (error.message);
            }
        }

        App.app.display_page.remove_display ();
        display.disconnect_it ();
        display = null;
    }

    protected void create_display_config (string? uuid = null)
        requires (this.config == null)
        ensures (this.config != null) {

        var group = "display";
        if (uuid != null)
            group += " " + uuid;

        config = new BoxConfig.with_group (source, group);
        if (config.last_seen_name != name)
            config.last_seen_name = name;

        if (uuid != null &&
            config.uuid != uuid)
            config.uuid = uuid;

        if (config.uuid == null)
            config.uuid = uuid_generate ();

        config.save ();
    }

    public bool is_running () {
        return state == MachineState.RUNNING;
    }

    public bool is_on () {
        return state == MachineState.RUNNING ||
            state == MachineState.PAUSED ||
            state == MachineState.SLEEPING;
    }

    private void save_pixbuf_as_screenshot (Gdk.Pixbuf? pixbuf) {
        try {
            pixbuf.save (get_screenshot_filename (), "png");
        } catch (GLib.Error error) {
            warning (error.message);
        }
    }

    /* Calculates the average energy intensity of a pixmap.
     * Being a square of an 8bit value this is a 16bit value. */
    private int pixbuf_energy (Gdk.Pixbuf pixbuf) {
        unowned uint8[] pixels = pixbuf.get_pixels ();
        int w = pixbuf.get_width ();
        int h = pixbuf.get_height ();
        int rowstride = pixbuf.get_rowstride ();
        int n_channels = pixbuf.get_n_channels ();

        int energy = 0;
        int row_start = 0;
        for (int y = 0; y < h; y++) {
            int row_energy = 0;
            int i = row_start;
            for (int x = 0; x < w; x++) {
                int max = int.max (int.max (pixels[i+0], pixels[i+1]), pixels[i+2]);
                row_energy += max * max;
                i += n_channels;
            }
            energy += row_energy / w;
            row_start += rowstride;
        }
        return energy / h;
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

            /* We don't accept black or almost-black screenshots as they are
               generally just screensavers/lock screens, which are not very helpful,
               and can easily be mistaken for turned off boxes.

               The number 100 is somewhat arbitrary, picked to not allow the gnome 3
               lock screen, nor a fullscreen white-on-black terminal with a single
               shell prompt, but do allow the terminal with a few lines of text.
            */
            if (pixbuf_energy (small_screenshot) < 50)
                return;

            orig_pixbuf = small_screenshot;
            pixbuf = draw_vm (small_screenshot, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
            machine_actor.set_screenshot (large_screenshot); // high resolution
            if (save)
                save_pixbuf_as_screenshot (small_screenshot);

        } else {
            orig_pixbuf = null;
            pixbuf = draw_stopped_vm ();
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
        if (large_screenshot != null)
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

            context.scale (2.0, 2.0);
            var grid = new Cairo.Pattern.for_surface (grid_surface);
            grid.set_extend (Cairo.Extend.REPEAT);
            context.set_source_rgba (0.2, 0.2, 0.2, 1);
            context.set_operator (Cairo.Operator.ADD);
            context.mask (grid);
        }

        return Gdk.pixbuf_get_from_surface (surface, 0, 0, width, height);
    }

    private static Gdk.Pixbuf draw_stopped_vm (int width = SCREENSHOT_WIDTH,
                                               int height = SCREENSHOT_HEIGHT) {
        var surface = new Cairo.ImageSurface (Cairo.Format.RGB24, width, height);
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

        config.delete ();
        try {
            FileUtils.unlink (get_screenshot_filename ());
        } catch (Boxes.Error e) {
            debug("Could not delete screenshot: %s", e.message);
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
    private GtkClutter.Actor? thumbnail;
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

        label = new Gtk.Label (machine.name);
        label.modify_fg (Gtk.StateType.NORMAL, get_color ("white"));
        machine.bind_property ("name", label, "label", BindingFlags.DEFAULT);
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
                machine.connect_display.begin ();

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

    public void update_thumbnail (Gtk.Widget widget, bool zoom = true) {
        if (thumbnail != null) {
            actor_remove (thumbnail);
            thumbnail.contents = null;
        }

        if (ui_state == UIState.PROPERTIES) {
            thumbnail = new GtkClutter.Actor.with_contents (widget);
            var click = new Clutter.ClickAction ();
            thumbnail.add_action (click);
            click.clicked.connect (() => {
                App.app.ui_state = Boxes.UIState.DISPLAY;
            });
            thumbnail.name = "properties-thumbnail";
            thumbnail.x_align = Clutter.ActorAlign.FILL;
            thumbnail.y_align = Clutter.ActorAlign.FILL;
            App.app.overlay_bin_actor.add_child (thumbnail);

            machine.display.set_enable_inputs (widget, false);

            Boxes.ActorFunc update_screenshot_alloc = (thumbnail) => {
                Gtk.Allocation alloc;

                App.app.properties.screenshot_placeholder.get_allocation (out alloc);
                App.app.topbar.actor.show ();

                // We disable implicit animations while setting the
                // properties because we don't want to animate these individually
                // we just want them to change instantly, causing a relayout
                // and recalculation of the allocation rect, which will then
                // be animated. Animating a rectangle between two states and
                // animating position and size individually looks completely
                // different.
                var d = thumbnail.get_easing_duration ();
                thumbnail.set_easing_duration (0);
                thumbnail.fixed_x = alloc.x;
                thumbnail.fixed_y = alloc.y;
                thumbnail.min_width = thumbnail.natural_width = alloc.width;
                thumbnail.min_height = thumbnail.natural_height = alloc.height;
                thumbnail.set_easing_duration (d);
            };

            if (track_screenshot_id != 0)
                App.app.properties.screenshot_placeholder.disconnect (track_screenshot_id);
            track_screenshot_id = App.app.properties.screenshot_placeholder.size_allocate.connect (() => {
                // We need to update in an idle to avoid changing layout stuff in a layout cycle
                // (i.e. inside the size_allocate)
                Idle.add_full (Priority.HIGH, () => {
                    update_screenshot_alloc (thumbnail);
                    return false;
                });
            });

            if (!zoom) {
                thumbnail.set_easing_duration (0);
                update_screenshot_alloc (thumbnail);
            }
        }
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
                actor.x_align = Clutter.ActorAlign.FILL;
                actor.y_align = Clutter.ActorAlign.FILL;
                actor.natural_width_set = false;
                actor.natural_height_set = false;
            } else {
                if (thumbnail != null) {
                    // zoom in, back from properties

                    App.app.properties.screenshot_placeholder.disconnect (track_screenshot_id);
                    track_screenshot_id = 0;

                    thumbnail.set_easing_duration (App.app.duration);
                    thumbnail.x_align = Clutter.ActorAlign.FILL;
                    thumbnail.y_align = Clutter.ActorAlign.FILL;
                    thumbnail.fixed_position_set = false;
                    thumbnail.min_width_set = thumbnail.natural_width_set = false;
                    thumbnail.min_height_set = thumbnail.natural_height_set = false;

                    thumbnail.transitions_completed.connect (() => {
                        var widget = thumbnail.contents;
                        thumbnail.contents = null;
                        thumbnail.destroy ();
                        thumbnail = null;
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
            if (widget == null) {
                if (previous_ui_state == UIState.WIZARD) {
                    // FIXME: We should draw a CD instead as in the mockup:
                    //        https://github.com/gnome-design-team/gnome-mockups/raw/master/boxes/boxes-install5.5.png
                }

                break;
            }

            update_thumbnail (widget);
            Clutter.ActorBox box = { 0, 0,  width, height};
            thumbnail.allocate (box, 0);

            // Temporarily hide toolbar in fullscreen so that the the animation
            // actor doesn't get pushed down before zooming to the sidebar
            if (App.app.fullscreen)
                App.app.topbar.actor.hide ();

            thumbnail.set_easing_mode (Clutter.AnimationMode.LINEAR);
            thumbnail.set_easing_duration (App.app.duration);
            ulong completed_id = 0;
            completed_id = thumbnail.transitions_completed.connect (() => {
                thumbnail.disconnect (completed_id);
                thumbnail.set_easing_duration (0);
            });

            thumbnail.show ();

            break;

        default:
            break;
        }
    }
}
