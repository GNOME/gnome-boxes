// This file is part of GNOME Boxes. License: LGPLv2+
using Gdk;
using Gtk;

private abstract class Boxes.Machine: Boxes.CollectionItem, Boxes.IPropertiesProvider {
    const uint AUTOSAVE_TIMEOUT = 60; // seconds

    public Boxes.CollectionSource source;
    public Boxes.BoxConfig config;
    public Gdk.Pixbuf? pixbuf { get; set; }
    public MachineThumbnailer thumbnailer { get; private set; }
    public bool stay_on_display;
    public string? info { get; protected set; }
    public string? status { get; set; }
    public virtual bool suspend_at_exit { get { return false; } }

    public virtual bool can_save { get { return false; } }
    public abstract bool can_restart { get; }
    public abstract bool can_clone { get; }
    public bool can_delete { get; set; default = true; }
    public bool under_construction { get; protected set; default = false; }

    private Cancellable auth_cancellable = new Cancellable ();
    private Secret.Schema secret_auth_schema
            = new Secret.Schema ("org.gnome.Boxes",
                                 Secret.SchemaFlags.NONE,
                                 "gnome-boxes-machine-uuid", Secret.SchemaAttributeType.STRING);

    public signal void got_error (string message);

    protected virtual bool should_autosave {
        get {
            return (can_save && is_running && autosave_timeout_id == 0);
        }
    }

    public bool is_connected {
        get {
            if (display == null)
                return false;

            return display.connected;
        }
    }

    public bool is_running {
        get {
            return state == MachineState.RUNNING;
        }
    }

    public bool is_on {
        get {
            return state == MachineState.RUNNING ||
                state == MachineState.PAUSED ||
                state == MachineState.SLEEPING;
        }
    }

    public bool is_stopped {
        get {
            return state == Machine.MachineState.FORCE_STOPPED || state == Machine.MachineState.STOPPED;
        }
    }

    public virtual bool is_local {
        get {
            // If the adress is in the 127.0.0.0 block or is localhost, then it is local
            if (/:\/\/(127\.\d+\.\d+\.\d+|localhost)/i.match (source.uri))
                return true;

            return false;
        }
    }

    private ulong show_id;
    private ulong hide_id;
    private ulong disconnected_id;
    private ulong need_password_id;
    private ulong need_username_id;
    private ulong ui_state_id;
    private ulong got_error_id;
    private ulong auth_failed_id;
    private uint screenshot_id;
    public const int SCREENSHOT_WIDTH = 180;
    public const int SCREENSHOT_HEIGHT = 134;
    public const int CENTERED_EMBLEM_SIZE = 32;
    public const int EMBLEM_SIZE = 16;
    private static Cairo.Surface grid_surface;
    private bool updating_screenshot;
    private string username;
    private string password;

    private uint autosave_timeout_id;

    public Cancellable connecting_cancellable { get; protected set; }

    public enum MachineState {
        UNKNOWN,
        STOPPED,
        FORCE_STOPPED,
        RUNNING,
        PAUSED,
        SAVED,
        SLEEPING
    }

    [Flags]
    public enum ConnectFlags {
        NONE = 0,
        IGNORE_SAVED_STATE
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

            // If the display is active and the VM goes to a non-running
            // state, we got to exit, as there is no way for the user
            // to progress in the vm display anymore
            if (display != null && !stay_on_display &&
                window != null && // This being null would mean app is exitting & no window exists anymore
                window.current_item == this &&
                value != MachineState.RUNNING &&
                window.ui_state != UIState.PROPERTIES &&
                value != MachineState.UNKNOWN) {
                window.set_state (Boxes.UIState.COLLECTION);
            }
        }
    }

    private unowned AppWindow _window;
    public unowned AppWindow window {
        get { return _window ?? App.app.main_window; }
        set { _window = value; }
    }

    public bool deleted { get; private set; }

    protected void show_display () {

        switch (window.ui_state) {
        case Boxes.UIState.CREDS:
            window.set_state (Boxes.UIState.DISPLAY);
            show_display ();
            break;

        case Boxes.UIState.DISPLAY:
            var widget = display.get_display (0);
            widget_remove (widget);
            window.display_page.show_display (display, widget);
            window.topbar.status = this.name;
            widget.grab_focus ();

            break;

        case Boxes.UIState.PROPERTIES:
            var widget = display.get_display (0);
            widget_remove (widget);
            window.display_page.replace_display (display, widget);
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
                _display.disconnect (hide_id);
                hide_id = 0;
                _display.disconnect (disconnected_id);
                disconnected_id = 0;
                _display.disconnect (need_password_id);
                need_password_id = 0;
                _display.disconnect (need_username_id);
                need_username_id = 0;
                _display.disconnect (got_error_id);
                got_error_id = 0;
                _display.disconnect (auth_failed_id);
                auth_failed_id = 0;
            }

            _display = value;
            if (_display == null)
                return;

            // Translators: The %s will be expanded with the name of the vm
            window.topbar.status = _("Connecting to %s").printf (name);

            show_id = _display.show.connect ((id) => {
                if (window != null && window.current_item == this)
                    show_display ();
            });

            hide_id = _display.hide.connect ((id) => {
                if (window != null && window.current_item == this)
                    window.display_page.remove_display ();
            });

            got_error_id = _display.got_error.connect ((message) => {
                    got_error (message);
            });

            auth_failed_id = _display.auth_failed.connect ((message) => {
                delete_auth_credentials.begin ();

                window.set_state (Boxes.UIState.COLLECTION);
                window.notificationbar.display_error (_("Authentication failed: %s").printf (message));
            });

            disconnected_id = _display.disconnected.connect ((failed) => {
                message (@"display $name disconnected");
                if (window == null) // App exitting & no window exists anymore
                    return;

                if (window.ui_state == UIState.CREDS || window.ui_state == UIState.DISPLAY) {
                    if (!stay_on_display && window.current_item == this)
                        window.set_state (Boxes.UIState.COLLECTION);

                    if (failed)
                        window.notificationbar.display_error (_("Connection to “%s” failed").printf (name));
                }

                load_screenshot ();
		if (!stay_on_display) {
                    disconnect_display ();
                }
            });

            need_password_id = _display.notify["need-password"].connect (handle_auth);
            need_username_id = _display.notify["need-username"].connect (handle_auth);

            _display.username = username;
            _display.password = password;
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

    protected Machine (Boxes.CollectionSource source, string name, string? uuid = null) {
        this.name = name;
        this.source = source;
        this.connecting_cancellable = new Cancellable ();

        notify["ui-state"].connect (ui_state_changed);
        ui_state_id = App.app.main_window.notify["ui-state"].connect (() => {
            if (App.app.main_window.ui_state == UIState.DISPLAY)
                set_screenshot_enable (false);
            else
                set_screenshot_enable (true);
        });

        create_display_config (uuid);

        // This needs to be set after the 'config' prop has been set.
        thumbnailer = new MachineThumbnailer (this,
                                              SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT,
                                              CENTERED_EMBLEM_SIZE, EMBLEM_SIZE);

        notify["under-construction"].connect (() => {
            if (under_construction) {
                var inhibit_reason = _("Machine is under construction");
                App.app.inhibit (null, null, inhibit_reason);
            } else {
                App.app.uninhibit ();
            }
        });
    }

    protected void load_screenshot () {
        try {
            var screenshot = (state != MachineState.STOPPED && state != MachineState.FORCE_STOPPED) ?
                             new Gdk.Pixbuf.from_file (get_screenshot_filename ()) :
                             null;
            set_screenshot (screenshot, false);
        } catch (GLib.Error error) {
        }
    }

    protected void set_screenshot_enable (bool enable) {
        if (enable) {
            if (screenshot_id != 0)
                return;
            update_screenshot.begin (false, true);
            var interval = App.app.main_window.settings.get_int ("screenshot-interval");
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

    private bool saving;
    public async void save () throws GLib.Error {
        if (state == Machine.MachineState.SAVED) {
            debug ("Not saving '%s' since it's already in saved state.", name);
            return;
        }

        saving = true;
        update_status ();

        try {
            yield save_real ();
        } finally {
            saving = false;
            update_status ();
        }
    }

    public void schedule_autosave () {
        if (!should_autosave)
            return;

        debug ("Scheduling autosave for '%s'", name);
        autosave_timeout_id = Timeout.add_seconds (AUTOSAVE_TIMEOUT, () => {
            try_save.begin ();
            autosave_timeout_id = 0;

            return false;
        });
    }

    public void unschedule_autosave () {
        if (autosave_timeout_id == 0)
            return;

        debug ("Unscheduling autosave for '%s'", name);
        Source.remove (autosave_timeout_id);
        autosave_timeout_id = 0;
    }

    protected virtual async void save_real () throws GLib.Error {
    }

    // this implementation of take_screenshot is not really useful since
    // screenshots will only be taken while the box is maximized/fullscreen,
    // and the disconnect_display () logic takes care of taking a screenshot
    // just before going back to the collection view. Taking regular
    // screenshots can have its use in case of an abnormal gnome-boxes
    // termination.
    protected async virtual Gdk.Pixbuf? take_screenshot () throws GLib.Error {
        if (display == null)
            return null;

        return display.get_pixbuf (0);
    }

    public abstract List<Boxes.Property> get_properties (Boxes.PropertiesPage page);

    public abstract async void connect_display (ConnectFlags flags) throws GLib.Error;
    public abstract void restart ();
    public abstract async void clone ();

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

        if (window.current_item == this)
            window.display_page.remove_display ();
        if (!display.should_keep_alive ()) {
            display.disconnect_it ();
            display = null;
        } else {
            display.set_enable_audio (false);
        }

        window = null;
    }

    private void create_display_config (string? uuid = null)
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
            config.uuid = Uuid.string_random ();

        config.save ();
    }

    protected virtual void update_status () {
        if (saving)
            status = _("Saving…");
        else
            status = null;
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

    private void set_screenshot (Gdk.Pixbuf? large_screenshot, bool save) {
        if (large_screenshot != null) {
            var pw = large_screenshot.get_width ();
            var ph = large_screenshot.get_height ();
            var s = double.min ((double) SCREENSHOT_WIDTH / pw, (double) SCREENSHOT_HEIGHT / ph);
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
            if (save)
                save_pixbuf_as_screenshot (small_screenshot);

        } else {
            orig_pixbuf = null;
            pixbuf = draw_stopped_vm ();
        }
    }

    int screenshot_counter;
    private async void update_screenshot (bool force_save = false, bool first_check = false) {
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

        if (!is_running) {
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

    public virtual void delete (bool by_user = true) {
        deleted = true;

        set_screenshot_enable (false);
        if (ui_state_id != 0) {
            App.app.main_window.disconnect (ui_state_id);
            ui_state_id = 0;
        }

        delete_auth_credentials.begin ();

        config.delete ();
        try {
            FileUtils.unlink (get_screenshot_filename ());
        } catch (Boxes.Error e) {
            debug("Could not delete screenshot: %s", e.message);
        }
    }

    private GLib.Binding? name_status_bind;

    private void ui_state_changed () {
        if (name_status_bind != null) {
            var topbar = name_status_bind.target as Topbar;
            topbar.status = null;
            name_status_bind.unbind ();
            name_status_bind = null;
        }

        switch (ui_state) {
        case UIState.CREDS:
            window.below_bin.set_visible_child_name ("connecting-page");
            try_connect_display.begin ();

            break;
        case Boxes.UIState.DISPLAY:
            if (previous_ui_state == UIState.PROPERTIES)
                window.below_bin.set_visible_child_name ("display-page");
            if (window.current_item == this)
                name_status_bind = bind_property ("name", window.topbar, "status", BindingFlags.SYNC_CREATE);

            break;

        case UIState.COLLECTION:
            if (auth_notification != null)
                auth_notification.dismiss ();
            disconnect_display ();

            auth_cancellable.cancel ();
            auth_cancellable = new Cancellable ();

            break;
        }
    }

    private async void try_connect_display (ConnectFlags flags = ConnectFlags.NONE) {
        try {
            yield connect_display (flags);
        } catch (Boxes.Error.RESTORE_FAILED e) {
            var message = _("“%s” could not be restored from disk\nTry without saved state?").printf (name);
            var notification = window.notificationbar.display_for_action (message, _("Restart"), () => {
                try_connect_display.begin (flags | Machine.ConnectFlags.IGNORE_SAVED_STATE);
            });
            notification.dismissed.connect (() => {
                window.set_state (UIState.COLLECTION);
            });
        } catch (Boxes.Error.START_FAILED e) {
            warning ("Failed to start %s: %s", name, e.message);
            window.set_state (UIState.COLLECTION);

            var msg = _("Failed to start “%s”").printf (name);
            if (this is LibvirtMachine) {
                Notification.OKFunc troubleshoot = () => {
                    window.current_item = this;
                    window.show_properties ();

                    var libvirt_machine = this as LibvirtMachine;
                    var logs = libvirt_machine.properties.collect_logs ();
                    window.props_window.show_troubleshoot_log (logs);
                };

                window.notificationbar.display_for_action (msg, _("Troubleshooting Log"), (owned) troubleshoot, null);
            } else {
                window.notificationbar.display_error (msg);
            }
        } catch (GLib.Error e) {
            warning ("Failed to connect to %s: %s", name, e.message);
            window.set_state (UIState.COLLECTION);
            window.notificationbar.display_error (_("Connection to “%s” failed").printf (name));
        }
    }

    private void store_auth_credentials () {
        if (this.password == "" || this.password == null)
            return;

        var builder = new GLib.VariantBuilder (GLib.VariantType.VARDICT);

        if (this.username != null)
            builder.add ("{sv}", "username", new GLib.Variant ("s", this.username));

        builder.add ("{sv}", "password", new GLib.Variant ("s", this.password));

        var credentials_str = builder.end ().print (true);

        var label = ("GNOME Boxes credentials for '%s'").printf (config.uuid);
        Secret.password_store.begin (secret_auth_schema,
                                     Secret.COLLECTION_DEFAULT,
                                     label,
                                     credentials_str,
                                     null,
                                     (obj, res) => {
            try {
                Secret.password_store.end (res);
            } catch (GLib.Error error) {
                warning ("Failed to store password for '%s' in the keyring: %s", config.uuid, error.message);
            }
        }, "gnome-boxes-machine-uuid", config.uuid);
    }

    private Boxes.AuthNotification auth_notification;

    private void handle_auth () {
        if (auth_notification != null)
            return;
        var need_username = display.need_username;
        if (!display.need_username && !display.need_password)
            return;
        display = null;

        AuthNotification.AuthFunc auth_func = (username, password) => {
            if (username != "")
                this.username = username;
            if (password != "")
                this.password = password;

            try_connect_display.begin ();

            /* Maybe this can be an optional preference with a toggle in the UI. */
            store_auth_credentials ();
        };

        Notification.DismissFunc dismiss_func = () => {
            auth_notification = null;
            window.set_state (UIState.COLLECTION);
        };

        Secret.password_lookup.begin (secret_auth_schema, auth_cancellable, (obj, res) => {
            try {
                var parsing_error = new Boxes.Error.INVALID ("couldn't unpack a string for the machine credentials");
                var credentials_str = Secret.password_lookup.end (res);
                if (credentials_str == null || credentials_str == "")
                    throw parsing_error;

                try {
                    var credentials_variant = GLib.Variant.parse (null, credentials_str, null, null);

                    string username_str;
                    credentials_variant.lookup ("username", "s", out username_str);
                    if (username_str != null && username_str != "")
                        this.username = username_str;

                    string password_str;
                    credentials_variant.lookup ("password", "s", out password_str);
                    if (password_str != null && password_str != "")
                        this.password = password_str;

                    try_connect_display.begin ();
                } catch (GLib.Error error) {
                    throw parsing_error;
                }
            } catch (GLib.Error error) {
                debug ("No credentials found in keyring. Prompting user.");

                // Translators: %s => name of launched box
                var auth_string = _("“%s” requires authentication").printf (name);
                auth_notification = window.notificationbar.display_for_auth (auth_string,
                                                                             (owned) auth_func,
                                                                             (owned) dismiss_func,
                                                                             need_username);
            }
        }, "gnome-boxes-machine-uuid", config.uuid);
    }

    private async void delete_auth_credentials () {
        if (config.uuid == null) {
            return;
        }

        try {
            yield Secret.password_clear (secret_auth_schema, null,
                                         "gnome-boxes-machine-uuid", config.uuid);

            if (auth_notification != null) {
                auth_notification.dismiss ();
                auth_notification = null;
            }
        } catch (GLib.Error error) {
            debug ("Failed to delete credentials for machine %s: %s", config.uuid, error.message);
        }
    }

    public override int compare (CollectionItem other) {
        if (other is Machine) {
            var machine = other as Machine;
            return config.compare (machine.config);
        } else
            return -1; // Machines are listed before non-machines
    }

    private async void try_save () {
        try {
            yield save ();
        } catch (GLib.Error error) {
            warning ("Failed to save '%s': %s", name, error.message);
        }
    }
}
