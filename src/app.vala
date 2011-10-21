// This file is part of GNOME Boxes. License: LGPLv2
using Config;
using Gtk;
using Gdk;
using GtkClutter;
using Clutter;
using GVir;

private enum Boxes.UIState {
    NONE,
    COLLECTION,
    CREDS,
    DISPLAY,
    SETTINGS,
    WIZARD
}

private errordomain Boxes.Error {
    INVALID
}

private enum Boxes.AppPage {
    MAIN,
    DISPLAY
}

private class Boxes.App: Boxes.UI {
    public override Clutter.Actor actor { get { return stage; } }
    public Gtk.Window window;
    public Gtk.Notebook notebook;
    public GtkClutter.Embed embed;
    public Clutter.Stage stage;
    public Clutter.State state;
    public Clutter.Box box; // the whole app box
    public CollectionItem current_item; // current object/vm manipulated
    public Topbar topbar;
    public Sidebar sidebar;
    public static const uint duration = 555;  // default to 1/2 for all transitions
    public static GLib.Settings settings;
    public Wizard wizard;
    public DisplayPage display_page;

    private Clutter.TableLayout box_table;
    private Collection collection;
    private CollectionView view;

    public App () {
        settings = new GLib.Settings ("org.gnome.boxes");
        setup_ui ();
        collection = new Collection (this);
        collection.item_added.connect ((item) => {
            item.actor.set_reactive (true);
            item.actor.button_press_event.connect ((actor, event) => {
                return item_clicked (item, event);
            });

            view.add_item (item);
        });

        setup_brokers ();
    }

    public void set_category (Category category) {
        topbar.label.set_text (category.name);
    }

    private async void setup_broker (string uri) {
        var connection = new GVir.Connection (uri);

        try {
            yield connection.open_async (null);
            connection.fetch_domains (null);
        } catch (GLib.Error e) {
            warning (e.message);
        }

        foreach (var domain in connection.get_domains ()) {
            var machine = new Machine (this, connection, domain);
            collection.add_item (machine);
        }
    }

    private async void setup_brokers () {
        foreach (var uri in settings.get_strv("broker-uris")) {
            setup_broker.begin (uri);
        }
    }

    private void setup_ui () {
        window = new Gtk.Window ();
        window.set_default_size (640, 480);
        notebook = new Gtk.Notebook ();
        notebook.show_border = false;
        notebook.show_tabs = false;
        window.add (notebook);
        embed = new GtkClutter.Embed ();
        notebook.append_page (embed, null);

        display_page = new DisplayPage (this);
        notebook.append_page (display_page.widget, null);

        stage = embed.get_stage () as Clutter.Stage;
        stage.set_color (gdk_rgba_to_clutter_color (get_boxes_bg_color ()));

        state = new Clutter.State ();
        state.set_duration (null, null, duration);

        window.destroy.connect (quit);
        window.key_press_event.connect (on_key_pressed);

        box_table = new Clutter.TableLayout ();
        box = new Clutter.Box (box_table);
        box.add_constraint (new Clutter.BindConstraint (stage, BindCoordinate.SIZE, 0));
        stage.add_actor (box);

        topbar = new Topbar (this);
        sidebar = new Sidebar (this);
        view = new CollectionView (this);

        window.show_all ();

        wizard = new Wizard (this);
        ui_state = UIState.COLLECTION;
    }

    public override void ui_state_changed () {
        foreach (var o in new Boxes.UI[] { sidebar, topbar, view, wizard }) {
            o.ui_state = ui_state;
        }

        switch (ui_state) {
        case UIState.DISPLAY:
            box.set_layout_manager (new Clutter.FixedLayout ());
            state.set_state ("display");
            break;
        case UIState.CREDS:
            notebook.page = Boxes.AppPage.MAIN;
            box.set_layout_manager (box_table);
            state.set_state ("creds");
            break;
        case UIState.COLLECTION:
            if (current_item is Machine) {
                var machine = current_item as Machine;

                machine.connect_display = false;
                machine.update_screenshot.begin ();
            }
            notebook.page = Boxes.AppPage.MAIN;
            box.set_layout_manager (box_table);
            state.set_state ("collection");
            break;
        case UIState.WIZARD:
            notebook.page = Boxes.AppPage.MAIN;
            box.set_layout_manager (box_table);
            break;
        default:
            warning ("Unhandled UI state %s".printf (ui_state.to_string ()));
            break;
        }
    }

    public void quit () {
        Gtk.main_quit ();
    }

    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        if (event.keyval == F11_KEY) {
            if (WindowState.FULLSCREEN in window.get_window ().get_state ())
                window.unfullscreen ();
            else
                window.fullscreen ();

            return true;
        }

        return false;
    }

    private bool item_clicked (CollectionItem item, Clutter.ButtonEvent event) {
        if (ui_state == UIState.COLLECTION) {
            current_item = item;

            if (current_item is Machine) {
                var machine = current_item as Machine;

                machine.connect_display = true;
                ui_state = UIState.CREDS;

            } else
                warning ("unknown item, fix your code");
        }

        return false;
    }
}

private abstract class Boxes.UI: GLib.Object {
    public abstract Clutter.Actor actor { get; }

    private UIState _ui_state;
    [CCode (notify = false)]
    public UIState ui_state {
        get { return _ui_state; }
        set {
            if (_ui_state != value) {
                _ui_state = value;
                ui_state_changed ();
                notify_property ("ui-state");
            }
        }
    }

    public abstract void ui_state_changed ();
}

private class Boxes.DisplayPage: GLib.Object {
    public Gtk.Widget widget { get { return overlay; } }
    private Gtk.Overlay overlay;
    private Boxes.App app;
    private Gtk.EventBox event_box;
    private Gtk.Toolbar toolbar;
    private uint toolbar_show_id;
    private uint toolbar_hide_id;
    private ulong display_id;
    private Gtk.Label title;

    public DisplayPage (Boxes.App app) {
        this.app = app;

        event_box = new Gtk.EventBox ();
        event_box.set_events (Gdk.EventMask.POINTER_MOTION_MASK);
        event_box.above_child = true;
        event_box.event.connect ((event) => {
            if (event.type == Gdk.EventType.MOTION_NOTIFY) {
                var y = event.motion.y;

                if (y <= 20 && toolbar_show_id == 0) {
                    toolbar_event_stop ();
                    toolbar_show_id = Timeout.add (app.duration, () => {
                        toolbar.show_all ();
                        toolbar_show_id = 0;
                        return false;
                    });
                } else if (y > 5)
                    toolbar_event_stop (true, false);
            }

            if (event_box.get_child () != null)
                event_box.get_child ().event (event);
            return false;
        });
        overlay = new Gtk.Overlay ();
        overlay.margin = 0;
        overlay.add (event_box);

        toolbar = new Gtk.Toolbar ();
        toolbar.icon_size = Gtk.IconSize.MENU;
        toolbar.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        var back = new Gtk.ToolButton (null, null);
        back.icon_name =  "go-previous-symbolic";
        back.get_style_context ().add_class ("raised");
        back.clicked.connect ((button) => { app.ui_state = UIState.COLLECTION; });
        toolbar.insert (back, 0);
        toolbar.set_show_arrow (false);

        title = new Gtk.Label ("Display");
        var item = new Gtk.ToolItem ();
        item.add (title);
        item.set_expand (true);
        toolbar.insert (item, -1);

        toolbar.set_halign (Gtk.Align.FILL);
        toolbar.set_valign (Gtk.Align.START);

        overlay.add_overlay (toolbar);
        overlay.show_all ();
    }

    ~DisplayPage () {
        toolbar_event_stop ();
    }

    private void toolbar_event_stop (bool show = true, bool hide = true) {
        if (show) {
            if (toolbar_show_id != 0)
                GLib.Source.remove (toolbar_show_id);
            toolbar_show_id = 0;
        }

        if (hide) {
            if (toolbar_hide_id != 0)
                GLib.Source.remove (toolbar_hide_id);
            toolbar_hide_id = 0;
        }
    }

    public void show_display (Boxes.Machine machine, Gtk.Widget display) {
        remove_display ();
        toolbar.hide ();
        title.set_text (machine.name);
        event_box.add (display);
        event_box.show_all ();

        display_id = display.event.connect ((event) => {
            switch (event.type) {
            case Gdk.EventType.LEAVE_NOTIFY:
                toolbar_event_stop ();
                break;
            case Gdk.EventType.ENTER_NOTIFY:
                toolbar_event_stop ();
                toolbar_hide_id = Timeout.add (app.duration, () => {
                    toolbar.hide ();
                    toolbar_hide_id = 0;
                    return false;
                });
                break;
            }
            return false;
        });

        app.notebook.page = Boxes.AppPage.DISPLAY;
    }

    public void remove_display () {
        var display = event_box.get_child ();

        if (display_id != 0) {
            display.disconnect (display_id);
            display_id = 0;
        }
        if (display != null)
            event_box.remove (display);

    }

}
