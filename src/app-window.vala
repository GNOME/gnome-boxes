// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/app-window.ui")]
private class Boxes.AppWindow: Gtk.ApplicationWindow, Boxes.UI {
    public const uint TRANSITION_DURATION = 400; // milliseconds

    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    [CCode (notify = false)]
    public bool fullscreened {
        get { return WindowState.FULLSCREEN in get_window ().get_state (); }
        set {
            if (value)
                fullscreen ();
            else
                unfullscreen ();
        }
    }
    private bool maximized { get { return WindowState.MAXIMIZED in get_window ().get_state (); } }

    [GtkChild]
    public Searchbar searchbar;
    [GtkChild]
    public Topbar topbar;
    [GtkChild]
    public Notificationbar notificationbar;
    [GtkChild]
    public Sidebar sidebar;
    [GtkChild]
    public Wizard wizard;
    [GtkChild]
    public Properties properties;
    [GtkChild]
    public DisplayPage display_page;
    [GtkChild]
    public EmptyBoxes empty_boxes;
    [GtkChild]
    public Gtk.Stack below_bin;
    [GtkChild]
    private Gtk.Stack content_bin;
    [GtkChild]
    private Gtk.Box below_bin_hbox;
    [GtkChild]
    public CollectionView view;

    public GLib.Settings settings;

    private uint configure_id;
    public static const uint configure_id_timeout = 100;  // 100ms

    public AppWindow (Gtk.Application app) {
        Object (application: app, title: _("Boxes"));

        settings = new GLib.Settings ("org.gnome.boxes");

        notify["ui-state"].connect (ui_state_changed);

        Gtk.Window.set_default_icon_name ("gnome-boxes");
        Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;

        var provider = Boxes.load_css ("gtk-style.css");
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (),
                                                  provider,
                                                  600);

        // restore window geometry/position
        var size = settings.get_value ("window-size");
        if (size.n_children () == 2) {
            var width = (int) size.get_child_value (0);
            var height = (int) size.get_child_value (1);

            set_default_size (width, height);
        }

        if (settings.get_boolean ("window-maximized"))
            maximize ();

        var position = settings.get_value ("window-position");
        if (position.n_children () == 2) {
            var x = (int) position.get_child_value (0);
            var y = (int) position.get_child_value (1);

            move (x, y);
        }
    }

    public void setup_ui () {
        topbar.setup_ui ();
        wizard.setup_ui ();
        display_page.setup_ui ();
    }

    private void save_window_geometry () {
        int width, height, x, y;

        if (maximized)
            return;

        get_size (out width, out height);
        settings.set_value ("window-size", new int[] { width, height });

        get_position (out x, out y);
        settings.set_value ("window-position", new int[] { x, y });
    }

    private void ui_state_changed () {
        // The order is important for some widgets here (e.g properties must change its state before wizard so it can
        // flush any deferred changes for wizard to pick-up when going back from properties to wizard (review).
        foreach (var ui in new Boxes.UI[] { sidebar, topbar, view, properties, wizard, empty_boxes }) {
            ui.set_state (ui_state);
        }

        if (ui_state != UIState.COLLECTION)
            searchbar.search_mode_enabled = false;

        switch (ui_state) {
        case UIState.COLLECTION:
            if (App.app.collection.items.length != 0)
                below_bin.visible_child = view;
            else
                below_bin.visible_child = empty_boxes;
            fullscreened = false;
            view.visible = true;

            break;

        case UIState.CREDS:

            break;

        case UIState.WIZARD:
            below_bin.visible_child = below_bin_hbox;
            content_bin.visible_child = wizard;

            break;

        case UIState.PROPERTIES:
            below_bin.visible_child = below_bin_hbox;
            content_bin.visible_child = properties;

            break;

        case UIState.DISPLAY:
            if (maximized)
                fullscreened = true;

            break;

        default:
            warning ("Unhandled UI state %s".printf (ui_state.to_string ()));
            break;
        }
    }

    [GtkCallback]
    public bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        var default_modifiers = Gtk.accelerator_get_default_mod_mask ();

        if (event.keyval == Gdk.Key.F11) {
            fullscreened = !fullscreened;
            return true;
        } else if (event.keyval == Gdk.Key.Escape) {
            if (App.app.selection_mode && ui_state == UIState.COLLECTION)
               App.app.selection_mode = false;
        } else if (event.keyval == Gdk.Key.q &&
                   (event.state & default_modifiers) == Gdk.ModifierType.CONTROL_MASK) {
            App.app.quit_app ();
            return true;
        } else if (event.keyval == Gdk.Key.a &&
                   (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            App.app.quit_app ();
            return true;
        } else if (event.keyval == Gdk.Key.Left && // ALT + Left -> back
                   (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            App.window.topbar.click_back_button ();
            return true;
        } else if (event.keyval == Gdk.Key.Right && // ALT + Right -> forward
                   (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            App.window.topbar.click_forward_button ();
            return true;
        }

        return false;
    }

    [GtkCallback]
    private bool on_configure_event () {
        if (fullscreened)
            return false;

        if (configure_id != 0)
            GLib.Source.remove (configure_id);
        configure_id = Timeout.add (configure_id_timeout, () => {
            configure_id = 0;
            save_window_geometry ();

            return false;
        });

        return false;
     }

    [GtkCallback]
    private bool on_window_state_event (Gdk.EventWindowState event) {
        if (WindowState.FULLSCREEN in event.changed_mask)
            this.notify_property ("fullscreened");

        if (fullscreened)
            return false;

        settings.set_boolean ("window-maximized", maximized);
        return false;
    }

    [GtkCallback]
    private bool on_delete_event () {
        return App.app.quit_app ();
    }
}
