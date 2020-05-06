// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/app-window.ui")]
private class Boxes.AppWindow: Gtk.ApplicationWindow, Boxes.UI {
    public const uint TRANSITION_DURATION = 400; // milliseconds

    public enum ViewType {
        ICON = 1,
        LIST = 2,
    }

    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    // current object/vm manipulated
    private CollectionItem _current_item;
    public CollectionItem current_item {
        get {
            return _current_item;
        }

        set {
            if (_current_item != null) {
                _current_item.disconnect (machine_state_notify_id);
                _current_item.disconnect (machine_deleted_notify_id);
                machine_state_notify_id = 0;
                machine_deleted_notify_id = 0;
            }

            _current_item = value;
            if (_current_item != null) {
                var machine = (_current_item as Machine);

                machine_state_notify_id = machine.notify["state"].connect (on_machine_state_notify);
                machine_deleted_notify_id = machine.notify["deleted"].connect (on_machine_deleted_notify);
            }
        }
    }
    public signal void item_selected (CollectionItem item);

    private GLib.Binding status_bind;
    private ulong got_error_id;
    private ulong machine_state_notify_id;
    private ulong machine_deleted_notify_id;

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

    private bool _selection_mode;
    public bool selection_mode { get { return _selection_mode; }
        set {
            return_if_fail (ui_state == UIState.COLLECTION);

            _selection_mode = value;
        }
    }

    public Notificationbar notificationbar {
        get {
            switch (ui_state) {
            case UIState.PROPERTIES:
                return props_window.notificationbar;
            default:
                return _notificationbar;
            }
        }
    }

    public PropertiesWindow  props_window;

    [GtkChild]
    public Searchbar searchbar;
    [GtkChild]
    public Topbar topbar;
    [GtkChild]
    public Selectionbar selectionbar;
    [GtkChild]
    public DisplayPage display_page;
    [GtkChild]
    public EmptyBoxes empty_boxes;
    [GtkChild]
    public TroubleshootView troubleshoot_view;
    [GtkChild]
    public Gtk.Stack below_bin;
    [GtkChild]
    private IconView icon_view;
    [GtkChild]
    private ListView list_view;

    public ViewType view_type { get; set; default = ViewType.ICON; }

    public ICollectionView view {
        get {
            switch (view_type) {
            default:
            case ViewType.ICON:
                return icon_view;
            case ViewType.LIST:
                return list_view;
            }
        }
    }

    private ICollectionView[] views;

    public GLib.Settings settings;

    public bool first_run {
        get { return settings.get_boolean ("first-run"); }
        set { settings.set_boolean ("first-run", value); }
    }

    [GtkChild]
    private Notificationbar _notificationbar;

    private uint configure_id;
    public const uint configure_id_timeout = 100;  // 100ms

    private Gtk.WindowGroup group;

    public AppWindow (Gtk.Application app) {
        Object (application:  app,
                title:        _("Boxes"),
                // Can't be set from template: https://bugzilla.gnome.org/show_bug.cgi?id=754426#c14
                show_menubar: false);

        settings = new GLib.Settings ("org.gnome.boxes");

        notify["ui-state"].connect (ui_state_changed);

        Gtk.Window.set_default_icon_name (Config.APPLICATION_ID);
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

        views = { icon_view, list_view };

        if (app.application_id == "org.gnome.BoxesDevel") {
            get_style_context ().add_class ("devel");
        }
    }

    public void setup_ui () {
        topbar.setup_ui (this);
        display_page.setup_ui (this);
        icon_view.setup_ui (this);
        list_view.setup_ui (this);
        selectionbar.setup_ui (this);
        searchbar.setup_ui (this);
        empty_boxes.setup_ui (this);
        troubleshoot_view.setup_ui (this);
        notificationbar.searchbar = searchbar;

        group = new Gtk.WindowGroup ();
        group.add_window (this);
        props_window = new PropertiesWindow (this);
        group.add_window (props_window);

        notify["view-type"].connect (ui_state_changed);
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
        foreach (var ui in new Boxes.UI[] { topbar,
                                            icon_view,
                                            list_view,
                                            props_window,
                                            //wizard_window,
                                            empty_boxes }) {
            ui.set_state (ui_state);
        }

        if (ui_state != UIState.COLLECTION)
            searchbar.search_mode_enabled = false;

        var machine = (current_item is Machine)? current_item as Machine : null;

        switch (ui_state) {
        case UIState.COLLECTION:
            if (App.app.collection.length != 0)
                below_bin.visible_child = view;
            else
                below_bin.visible_child = empty_boxes;
            fullscreened = false;
            foreach_view ((view) => { view.visible = true; });

            if (status_bind != null) {
                status_bind.unbind ();  // FIXME: We shouldn't neeed to explicitly unbind (Vala bug?)
                status_bind = null;
            }
            topbar.status = _("Boxes");
            var a11y = get_accessible ();
            a11y.accessible_name = _("Boxes");

            if (machine != null) {
                if (got_error_id != 0) {
                    machine.disconnect (got_error_id);
                    got_error_id = 0;
                }

                machine.connecting_cancellable.cancel (); // Cancel any in-progress connections
                machine.schedule_autosave ();
            }

            break;

        case UIState.CREDS:
        case UIState.DISPLAY:
        case UIState.WIZARD:
        case UIState.PROPERTIES:
            if (current_item != null) {
                var current_machine = current_item as Machine;
                current_machine.unschedule_autosave ();
            }

            break;

        case UIState.TROUBLESHOOT:
            below_bin.visible_child = troubleshoot_view;

            break;

        default:
            warning ("Unhandled UI state %s".printf (ui_state.to_string ()));
            break;
        }

        if (machine != null && this == machine.window)
            current_item.set_state (ui_state);
    }

    public void foreach_view (Func<ICollectionView> func) {
        foreach (var view in views)
            func (view);
    }

    public void show_remote_connection_assistant (string? uri = null) {
        new Boxes.RemoteConnectionAssistant (this, uri).run ();
    }

    public void show_vm_assistant (string? path = null) {
        new Boxes.VMAssistant (this, path).run ();
    }

    public void show_welcome_tutorial () {
        if (first_run) {
            new Boxes.WelcomeTutorial (this).run ();

            first_run = !first_run;
        }
    }

    public void show_properties () {
        if (current_item != null) {
            if (ui_state == UIState.COLLECTION && selection_mode)
                selection_mode = false;
            set_state (UIState.PROPERTIES);

            return;
        }

        var selected_items = view.get_selected_items ();

        if (ui_state == UIState.COLLECTION && selection_mode)
            selection_mode = false;

        // Show for the first selected item
        foreach (var item in selected_items) {
            current_item = item;
            set_state (UIState.PROPERTIES);
            break;
        }
    }

    public void show_send_file () {
        var dialog = new Gtk.FileChooserDialog (
                _("Select files to transfer"), this, Gtk.FileChooserAction.OPEN,
                _("_Cancel"),
                Gtk.ResponseType.CANCEL,
                _("_Open"),
                Gtk.ResponseType.ACCEPT);
        dialog.select_multiple = true;

        if (dialog.run () == Gtk.ResponseType.ACCEPT) {
            SList<string> uris = dialog.get_uris ();

            GLib.List<string> uris_param = null;
            foreach (var uri in uris) {
                uris_param.append (uri);
            }

            var machine = current_item as Machine;
            machine.display.transfer_files (uris_param);
        }

        dialog.destroy ();
    }

    public void connect_to (Machine machine) {
        current_item = machine;
        machine.window = this;
        machine.unschedule_autosave ();

        var a11y = get_accessible ();
        a11y.accessible_name = machine.name;

        // Track machine status in toolbar
        status_bind = machine.bind_property ("status", topbar, "status", BindingFlags.SYNC_CREATE);

        got_error_id = machine.got_error.connect ( (message) => {
            notificationbar.display_error (message);
        });

        if (ui_state != UIState.CREDS)
            set_state (UIState.CREDS); // Start the CREDS state
    }

    public void select_item (CollectionItem item) {
        if (ui_state != UIState.COLLECTION || selection_mode)
            return;

        return_if_fail (item is Machine);

        var machine = item as Machine;

        if (machine.window != App.app.main_window) {
            machine.window.present ();

            return;
        }

        current_item = item;

        if (current_item is Machine)
            connect_to (machine);
        else
            warning ("unknown item, fix your code");

        item_selected (item);
    }

    public void filter (string text) {
        foreach_view ((view) => { view.filter.text = text; });
    }

    [GtkCallback]
    public bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        var default_modifiers = Gtk.accelerator_get_default_mod_mask ();
        var direction = get_direction ();

        if (event.keyval == Gdk.Key.F11) {
            fullscreened = !fullscreened;

            return true;
        } else if (event.keyval == Gdk.Key.F1) {
            App.app.activate_action ("help", null);

            return true;
        } else if (event.keyval == Gdk.Key.F10) {
            topbar.pop_main_menu ();

            return true;
        } else if (event.keyval == Gdk.Key.q &&
                   (event.state & default_modifiers) == Gdk.ModifierType.CONTROL_MASK) {
            if (ui_state == UIState.DISPLAY)
                return false;

            App.app.quit_app ();

            return true;
        } else if (event.keyval == Gdk.Key.n &&
                   (event.state & default_modifiers) == Gdk.ModifierType.CONTROL_MASK) {
            show_vm_assistant ();

            return true;
        } else if (event.keyval == Gdk.Key.N &&
                   (event.state & default_modifiers) == (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
            show_remote_connection_assistant ();

            return true;
        } else if (event.keyval == Gdk.Key.f &&
                   (event.state & default_modifiers) == Gdk.ModifierType.CONTROL_MASK) {
            topbar.click_search_button ();

            return true;
        } else if (event.keyval == Gdk.Key.a &&
                   (event.state & default_modifiers) == Gdk.ModifierType.CONTROL_MASK) {
            selection_mode = true;
            foreach_view ((view) => { view.select_all (); });

            return true;
        } else if (event.keyval == Gdk.Key.A &&
                   (event.state & default_modifiers) == (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
            foreach_view ((view) => { view.unselect_all (); });

            return true;
        } else if (((direction == Gtk.TextDirection.LTR && // LTR
                     event.keyval == Gdk.Key.Left) ||      // ALT + Left -> back
                    (direction == Gtk.TextDirection.RTL && // RTL
                     event.keyval == Gdk.Key.Right)) &&    // ALT + Right -> back
                   (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            topbar.click_back_button ();
            return true;
        } else if (event.keyval == Gdk.Key.Escape) { // ESC -> cancel
            topbar.click_cancel_button ();
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
        return_val_if_fail (current_item == null || current_item is Machine, false);

        if (current_item != null) {
            var machine = current_item as Machine;

            machine.window = null;
            machine.schedule_autosave ();

            machine.disconnect (machine_state_notify_id);
            machine_state_notify_id = 0;
            machine.disconnect (machine_deleted_notify_id);
            machine_deleted_notify_id = 0;
        }

        return App.app.remove_window (this);
    }

    private void on_machine_state_notify () {
       var current_machine = current_item as Machine;
       if (this != App.app.main_window && current_machine.state != Machine.MachineState.RUNNING)
           on_delete_event ();
    }

    private void on_machine_deleted_notify () {
       var current_machine = current_item as Machine;
       if (this != App.app.main_window && current_machine.deleted)
           on_delete_event ();
    }
}
