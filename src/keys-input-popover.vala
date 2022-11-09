// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.KeysInputPopover: Gtk.Popover {
    private const GLib.ActionEntry[] action_entries = {
        {"ctrl+alt+backspace", ctrl_alt_backspace_activated},
        {"ctrl+alt+del", ctrl_alt_del_activated},

        {"ctrl+alt+f1", ctrl_alt_fn_activated},
        {"ctrl+alt+f2", ctrl_alt_fn_activated},
        {"ctrl+alt+f3", ctrl_alt_fn_activated},
        {"ctrl+alt+f6", ctrl_alt_fn_activated},
        {"ctrl+alt+f7", ctrl_alt_fn_activated},
        {"ctrl+alt+f9", ctrl_alt_fn_activated},
    };

    private AppWindow window;
    private GLib.SimpleActionGroup action_group;

    public KeysInputPopover (AppWindow window) {
        this.window = window;

        action_group = new GLib.SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        this.insert_action_group ("key", action_group);

        var menu = new GLib.Menu ();

        menu.append (_("Ctrl + Alt + Backspace"), "key.ctrl+alt+backspace");
        menu.append (_("Ctrl + Alt + Del"), "key.ctrl+alt+del");

        // New section
        var section = new GLib.Menu ();
        section.append (_("Ctrl + Alt + F1"), "key.ctrl+alt+f1");
        section.append (_("Ctrl + Alt + F2"), "key.ctrl+alt+f2");
        section.append (_("Ctrl + Alt + F3"), "key.ctrl+alt+f3");
        section.append (_("Ctrl + Alt + F6"), "key.ctrl+alt+f6");
        section.append (_("Ctrl + Alt + F7"), "key.ctrl+alt+f7");
        section.append (_("Ctrl + Alt + F9"), "key.ctrl+alt+f9");
        menu.append_section (null, section);

        bind_model (menu, null);

        var a11y = get_accessible ();
        a11y.role = Atk.Role.POPUP_MENU;
        // Translators: Accessibility name for context menu with a set of keyboard combos (that would normally be
        //              intercepted by host/client, to send to the box.
        a11y.name = _("Send key combinations");
    }

    private void ctrl_alt_backspace_activated () {
        uint[] keyvals = { Gdk.Key.Control_L, Gdk.Key.Alt_L, Gdk.Key.BackSpace };

        send_keys (keyvals);
    }

    private void ctrl_alt_del_activated () {
        uint[] keyvals = { Gdk.Key.Control_L, Gdk.Key.Alt_L, Gdk.Key.Delete };

        send_keys (keyvals);
    }

    private void ctrl_alt_fn_activated (GLib.SimpleAction action) {
        uint[] keyvals = { Gdk.Key.Control_L, Gdk.Key.Alt_L, 0 };

        if (action.name[action.name.length - 1] == '1')
            keyvals[2] = Gdk.Key.F1;
        else if (action.name[action.name.length - 1] == '2')
            keyvals[2] = Gdk.Key.F2;
        else if (action.name[action.name.length - 1] == '3')
            keyvals[2] = Gdk.Key.F3;
        else if (action.name[action.name.length - 1] == '6')
            keyvals[2] = Gdk.Key.F6;
        else if (action.name[action.name.length - 1] == '7')
            keyvals[2] = Gdk.Key.F7;
        else if (action.name[action.name.length - 1] == '9')
            keyvals[2] = Gdk.Key.F9;
        else {
            warn_if_reached ();

            return;
        }

        send_keys (keyvals);
    }

    private void send_keys (uint[] keyvals) {
        var machine = window.current_item as Machine;
        return_if_fail (machine != null && machine.display != null);

        machine.display.send_keys (keyvals);
    }
}
