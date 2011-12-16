// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

private class Boxes.DisplayPage: GLib.Object {
    public Widget widget { get { return overlay; } }

    private Overlay overlay;
    private Boxes.App app;
    private EventBox event_box;
    private Toolbar toolbar;
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

        var left_group = new ToolItem ();
        toolbar.insert (left_group, 0);

        var center_group = new ToolItem ();
        center_group.set_expand (true);
        toolbar.insert (center_group, -1);

        var right_group = new ToolItem ();
        toolbar.insert (right_group, -1);

        var size_group = new SizeGroup (SizeGroupMode.HORIZONTAL);
        size_group.add_widget (left_group);
        size_group.add_widget (right_group);

        var left_box = new Box (Orientation.HORIZONTAL, 0);
        left_group.add (left_box);

        var back = new Button ();
        back.add (new Image.from_icon_name ("go-previous-symbolic",
                                            IconSize.MENU));
        back.get_style_context ().add_class ("raised");
        back.clicked.connect ((button) => { app.ui_state = UIState.COLLECTION; });
        left_box.pack_start (back, false, false, 0);

        /* center title - unfortunately, metacity doesn't even center its
           own title.. sad panda */
        title = new Label ("Display");
        center_group.add (title);

        var right_box = new Box (Orientation.HORIZONTAL, 12);
        right_group.add(right_box);

        var btn = new Button ();
        btn.add (new Image.from_icon_name ("view-fullscreen-symbolic",
                                           IconSize.MENU));
        btn.get_style_context ().add_class ("raised");
        btn.clicked.connect ((button) => { app.fullscreen = !app.fullscreen; });
        right_box.pack_start (btn, false, false, 0);

        var props = new Button ();
        props.add (new Image.from_icon_name ("utilities-system-monitor-symbolic",
                                             IconSize.MENU));
        props.get_style_context ().add_class ("raised");
        props.clicked.connect ((button) => { app.ui_state = UIState.PROPERTIES; });
        right_box.pack_start (props, false, false, 0);

        toolbar.set_show_arrow (false);
        toolbar.set_valign (Gtk.Align.START);

        overlay.add_overlay (toolbar);
        overlay.show_all ();
    }

    void set_toolbar_visible(bool visible) {
        toolbar.visible = visible;
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
