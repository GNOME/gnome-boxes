// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.Searchbar: Boxes.UI {
    public override Clutter.Actor actor { get { return gtk_actor; } }
    private GtkClutter.Actor gtk_actor;
    private Gd.TaggedEntry entry;

    private uint refilter_delay_id;
    static const uint refilter_delay = 200; // in ms

    public Searchbar () {
        setup_searchbar ();

        App.app.window.key_press_event.connect (on_app_key_pressed);
        entry.notify["text"].connect ( () => {
                if (refilter_delay_id != 0)
                    Source.remove (refilter_delay_id);

                if (text == "")
                    refilter ();
                else
                    refilter_delay_id = Timeout.add (refilter_delay, refilter);
        });
        entry.activate.connect ( () => {
            App.app.view.activate ();
        });
    }

    private bool refilter () {
        App.app.filter.text = text;
        App.app.view.refilter ();
        refilter_delay_id = 0;

        return false;
    }

    private bool _visible;
    public bool visible {
        get {
            return _visible;
        }
        set {
            if (_visible == value)
                return;

            App.app.searchbar_revealer.revealed = value;
            if (value)
                grab_focus ();
            else
                text = "";

            _visible = value;
        }
    }

    public string text {
        get { return entry.text; }
        set { entry.set_text (value); }
    }

    public void grab_focus () {
        Gd.entry_focus_hack (entry, Gtk.get_current_event_device ());
    }

    private bool on_app_key_pressed (Gtk.Widget widget, Gdk.EventKey event) {
        var handled = false;

        if (ui_state != UIState.COLLECTION)
            return handled;

        if (!entry.get_realized ()) {
            actor.show ();
            // should not needed since searchbar actor
            // is inside hidden revealer, but it ensure
            // it's not visible..
            actor.hide ();
        }

        var preedit_changed = false;
        var preedit_changed_id =
            entry.preedit_changed.connect (() => { preedit_changed = true; });

        var old_text = text;
        if (!visible)
            text = "";

        if (visible && event.keyval == Gdk.Key.Escape) {
            text = "";
            visible = false;
            return true;
        }

        var res = false;

        // Don't pass on keynav keys, or CTRL/ALT using keys to search
        if (event.keyval != Gdk.Key.Tab &&
            event.keyval != Gdk.Key.KP_Tab &&
            event.keyval != Gdk.Key.Up &&
            event.keyval != Gdk.Key.KP_Up &&
            event.keyval != Gdk.Key.Down &&
            event.keyval != Gdk.Key.KP_Down &&
            event.keyval != Gdk.Key.Left &&
            event.keyval != Gdk.Key.KP_Left &&
            event.keyval != Gdk.Key.Right &&
            event.keyval != Gdk.Key.KP_Right &&
            event.keyval != Gdk.Key.Home &&
            event.keyval != Gdk.Key.KP_Home &&
            event.keyval != Gdk.Key.End &&
            event.keyval != Gdk.Key.KP_End &&
            event.keyval != Gdk.Key.Page_Up &&
            event.keyval != Gdk.Key.KP_Page_Up &&
            event.keyval != Gdk.Key.Page_Down &&
            event.keyval != Gdk.Key.KP_Page_Down &&
            ((event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK)) == 0))
            res = entry.event ((Gdk.Event)(&event));
        var new_text = text;

        entry.disconnect (preedit_changed_id);

        if (((res && (new_text != old_text)) || preedit_changed)) {
            handled = true;
            if (!visible)
                visible = true;
            else
                grab_focus ();
        }

        return handled;
    }

    private void setup_searchbar () {
        var toolbar = new Gtk.Toolbar ();
        var widget = toolbar;
        toolbar.get_style_context ().add_class (Gtk.STYLE_CLASS_PRIMARY_TOOLBAR);

        var item = new Gtk.ToolItem ();
        toolbar.insert(item, 0);
        item.set_expand (true);

        // FIXME: https://bugzilla.gnome.org/show_bug.cgi?id=680595
        var margin = new Gd.MarginContainer ();
        item.add (margin);
        margin.min_margin = 6;
        margin.max_margin = 64;

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        margin.add (box);

        entry = new Gd.TaggedEntry ();
        entry.width_request = 260;
        entry.hexpand = true;
        box.add (entry);

        widget.show_all ();
        gtk_actor = new GtkClutter.Actor.with_contents (widget);
        gtk_actor.name = "searchbar";
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.COLLECTION:
            break;
        default:
            break;
        }
    }
}
