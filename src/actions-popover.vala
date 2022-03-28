// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.ActionsPopover: Gtk.Popover {
    private const GLib.ActionEntry[] action_entries = {
        {"open-in-new-win", open_in_new_win_activated},
        {"take_screenshot", take_screenshot_activated},
        {"force_shutdown",  force_shutdown_activated},
        {"delete",          delete_activated},
        {"clone",           clone_activated},
        {"preferences",     preferences_activated},
        {"restart",         restart_activated},
        {"send_file",       send_file_activated}

    };

    private AppWindow window;
    private GLib.SimpleActionGroup action_group;

    public ActionsPopover (AppWindow window) {
        this.window = window;

        action_group = new GLib.SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        this.insert_action_group ("box", action_group);

        var a11y = get_accessible ();
        a11y.role = Atk.Role.POPUP_MENU;
        // Translators: Accessibility name for context menu with box-related actions (e.g Pause, Delete etc)
        a11y.name = _("Box actions");
    }

    public void update_for_item (CollectionItem item) {
        return_if_fail (item is Machine);
        var machine = item as Machine;

        var menu = new GLib.Menu ();
        var section = new GLib.Menu ();

        var libvirt_machine = machine as LibvirtMachine;
        var importing = (machine is LibvirtMachine && libvirt_machine.importing);

        // Open in new Window
        if (window.ui_state != UIState.DISPLAY) {
            section.append (_("Open in New Window"), "box.open-in-new-win");
            var action = action_group.lookup_action ("open-in-new-win") as GLib.SimpleAction;
            action.set_enabled (!importing);
        } else {
            // Send files
            section.append (_("Send File…"), "box.send_file");
            var action = action_group.lookup_action ("send_file") as GLib.SimpleAction;
            action.set_enabled (machine.display.can_transfer_files);
            machine.display.notify["is-guest-agent-connected"].connect (() => {
                action.set_enabled (machine.display.can_transfer_files);
            });

            // Take Screenshot
            section.append (_("Take Screenshot"), "box.take_screenshot");
        }
        menu.append_section (null, section);

        // New section for force shutdown and delete
        section = new GLib.Menu ();

        if (machine is LibvirtMachine) {
            section.append (_("Force Shutdown"), "box.force_shutdown");
            var action = action_group.lookup_action ("force_shutdown") as GLib.SimpleAction;
            action.set_enabled (machine.is_running);
        }

        if (window.ui_state != UIState.DISPLAY) {
            // Clone
            var can_clone = machine.can_clone;
            if (machine is LibvirtMachine)
                can_clone = can_clone && !machine.is_running;

            section.append (_("Clone"), "box.clone");
            var action = action_group.lookup_action ("clone") as GLib.SimpleAction;
            action.set_enabled (can_clone);

            // Delete
            section.append (_("Delete"), "box.delete");
            action = action_group.lookup_action ("delete") as GLib.SimpleAction;
            action.set_enabled (machine.can_delete);
        } else {
            section.append (_("Restart"), "box.restart");
            var action = action_group.lookup_action ("restart") as GLib.SimpleAction;
            action.set_enabled (machine.can_restart);
        }

        menu.append_section (null, section);

        // Properties (in separate section)
        section = new GLib.Menu ();
        section.append (_("Preferences"), "box.preferences");
        menu.append_section (null, section);
        var action = action_group.lookup_action ("preferences") as GLib.SimpleAction;
        action.set_enabled (!importing);

        bind_model (menu, null);
        window.current_item = item;
    }

    private void open_in_new_win_activated () {
        App.app.open_in_new_window (window.current_item as Machine);
    }

    private string get_screenshot_filename () throws GLib.Error {
        // Translators: name of the folder under ~/Pictures for screenshots. This is the same folder where GNOME Shell saves screenshots.
        string dir_name = _("Screenshots");
        string path = Path.build_filename (GLib.Environment.get_user_special_dir (GLib.UserDirectory.PICTURES),
                                           dir_name);
        var dir = GLib.File.new_for_path (path);

        // Lets ensure that the "Screenshots" directory really exists.
        try {
            dir.make_directory_with_parents (null);
        } catch (GLib.Error error) {
            if (!(error is GLib.IOError.EXISTS))
                throw error;
        }

        var now = new GLib.DateTime.now_local ();
        var timestamp = now.format ("%Y-%m-%d %H-%M-%S");

        // Translators: %s => the timestamp of when the screenshot was taken.
        var filename =_("Screenshot from %s").printf (timestamp);

        return Path.build_filename (dir.get_path (), filename + ".png");
    }

    private void take_screenshot_activated () {
        var machine = window.current_item as Machine;
        try {
            Gdk.Pixbuf pixbuf = machine.display.get_pixbuf (0);
            pixbuf.save (get_screenshot_filename (), "png");
        } catch (GLib.Error error) {
            warning (error.message);
        }

        var ctx = window.below_bin.get_style_context ();
        ctx.add_class ("flash");
        Timeout.add (200, () => {
            ctx.remove_class ("flash");

            return false;
        });
    }

    private void force_shutdown_activated () {
        var machine = window.current_item as LibvirtMachine;

        machine.force_shutdown ();
    }

    private void restart_activated () {
        var machine = window.current_item as Machine;

        machine.restart ();
    }

    private void delete_activated () {
        window.set_state (UIState.COLLECTION);

        var items = new List<CollectionItem> ();
        items.append (window.current_item);

        App.app.delete_machines_undoable ((owned) items);
    }

    private void clone_activated () {
        var machine = window.current_item as Machine;

        machine.clone.begin ();
    }

    private void send_file_activated () {
        window.show_send_file ();
    }


    private void preferences_activated () {
        var machine = window.current_item as Machine;

        var preferences = new Boxes.PreferencesWindow () {
            machine = machine,
            transient_for = window,
        };
        preferences.present ();
    }
}
