// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

private class Boxes.DisplayPage: GLib.Object {
    public Widget widget { get { return overlay; } }

    private Overlay overlay;
    private Boxes.App app;
    private EventBox event_box;
    private Toolbar toolbar;
    private Toolbar title_toolbar;
    private uint toolbar_show_id;
    private uint toolbar_hide_id;
    private ulong display_id;
    private ulong cursor_id;
    private Label title;

    public DisplayPage (Boxes.App app) {
        this.app = app;

        event_box = new EventBox ();
        event_box.set_events (EventMask.POINTER_MOTION_MASK);
        event_box.above_child = true;
        event_box.event.connect ((event) => {
            if (event.type == EventType.MOTION_NOTIFY) {
                var y = event.motion.y;

                if (y == 0) {
                    toolbar_event_stop ();
                    set_toolbar_visible (true);
                } else if (!app.fullscreen && y <= 5 && toolbar_show_id == 0) {
                    toolbar_event_stop ();
                    toolbar_show_id = Timeout.add (1000, () => {
                        set_toolbar_visible (true);
                        toolbar_show_id = 0;
                        return false;
                    });
                } else if (y > 5) {
                    toolbar_event_stop (true, false);
                    if (toolbar_hide_id == 0)
                        toolbar_hide_id = Timeout.add (app.duration, () => {
                            set_toolbar_visible (false);
                            toolbar_hide_id = 0;
                            return false;
                        });
                }
            }

            if (event_box.get_child () != null)
                event_box.get_child ().event (event);

            return false;
        });
        overlay = new Overlay ();
        overlay.margin = 0;
        overlay.add (event_box);

        toolbar = new Toolbar ();
        toolbar.icon_size = IconSize.MENU;
        toolbar.get_style_context ().add_class (STYLE_CLASS_MENUBAR);

        var back = new ToolButton (null, null);
        back.icon_name = "go-previous-symbolic";
        back.get_style_context ().add_class ("raised");
        back.clicked.connect ((button) => { app.ui_state = UIState.COLLECTION; });
        toolbar.insert (back, 0);
        toolbar.set_show_arrow (false);

        /* this is quite insane to center the label and keep toolbar style... */
        /* unfortunately, metacity doesn't even center its own title.. sad panda */
        title_toolbar = new Toolbar ();
        title_toolbar.valign = Gtk.Align.START;
        title_toolbar.halign = Gtk.Align.CENTER;
        title_toolbar.get_style_context ().add_class (STYLE_CLASS_MENUBAR);
        title_toolbar.set_size_request (300, -1); // FIXME: can't put them in a sizegroup
        title = new Label ("Display");

        var title_item = new Gtk.ToolItem ();
        title_item.set_expand (true);
        title_item.add (title);
        title_toolbar.insert (title_item, -1);

        var sep = new Gtk.ToolItem ();
        sep.set_expand (true);
        toolbar.insert (sep, -1);

        /* this is quite crappy way of centering label. FIXME: event pass-through */
        var btn = new ToolButton (null, null);
        btn.icon_name = "view-fullscreen-symbolic";
        btn.get_style_context ().add_class ("raised");
        btn.clicked.connect ((button) => { app.fullscreen = !app.fullscreen; });
        toolbar.insert (btn, -1);

        toolbar.insert (new Gtk.SeparatorToolItem (), -1);

        var props = new ToolButton (null, null);
        props.icon_name = "utilities-system-monitor-symbolic";
        props.get_style_context ().add_class ("raised");
        props.clicked.connect ((button) => { app.ui_state = UIState.PROPERTIES; });
        toolbar.insert (props, -1);

        toolbar.set_show_arrow (false);
        toolbar.set_valign (Gtk.Align.START);

        overlay.add_overlay (toolbar);
        overlay.add_overlay (title_toolbar);
        overlay.show_all ();
    }

    void set_toolbar_visible(bool visible) {
        toolbar.visible = visible;
        title_toolbar.visible = visible;
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

    public void show () {
        app.notebook.page = Boxes.AppPage.DISPLAY;
    }

    public void show_display (Boxes.Machine machine, Widget display) {
        remove_display ();
        set_toolbar_visible (false);
        title.set_text (machine.name);
        event_box.add (display);
        event_box.show_all ();

        display_id = display.event.connect ((event) => {
            switch (event.type) {
            case EventType.LEAVE_NOTIFY:
                toolbar_event_stop ();
                break;
            case EventType.ENTER_NOTIFY:
                toolbar_event_stop ();
                break;
            }
            return false;
        });

        cursor_id = display.get_window ().notify["cursor"].connect (() => {
            event_box.get_window ().set_cursor (display.get_window ().cursor);
        });

        show ();
    }

    public Widget? remove_display () {
        var display = event_box.get_child ();

        if (display_id != 0) {
            display.disconnect (display_id);
            display_id = 0;
        }
        if (cursor_id != 0) {
            display.get_window ().disconnect (cursor_id);
            cursor_id = 0;
        }

        if (display != null)
            event_box.remove (display);

        return display;
    }

}
