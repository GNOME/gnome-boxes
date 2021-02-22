// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/selectionbar.ui")]
private class Boxes.Selectionbar: Gtk.Revealer {
    [GtkChild]
    private unowned Gtk.ToggleButton favorite_btn;
    [GtkChild]
    private unowned Gtk.Button pause_btn;
    [GtkChild]
    private unowned Gtk.Button remove_btn;
    [GtkChild]
    private unowned Gtk.Button open_btn;

    private AppWindow window;

    construct {
        App.app.notify["selected-items"].connect (() => {
            update_favorite_btn ();
            update_pause_btn ();
            update_delete_btn ();
            update_open_btn ();
        });
    }

    public void setup_ui (AppWindow window) {
        this.window = window;

        window.notify["selection-mode"].connect (() => {
            reveal_child = window.selection_mode;
        });
    }

    private bool ignore_favorite_btn_clicks;
    [GtkCallback]
    private void on_favorite_btn_clicked () {
        if (ignore_favorite_btn_clicks)
            return;

        foreach (var item in App.app.selected_items) {
            var machine = item as Machine;
            if (machine == null)
                continue;
            machine.config.set_category ("favorite", favorite_btn.active);
        }

        window.selection_mode = false;
    }

    [GtkCallback]
    private void on_pause_btn_clicked () {
        foreach (var item in App.app.selected_items) {
            var machine = item as Machine;
            if (machine == null)
                continue;
            machine.save.begin ( (obj, result) => {
                try {
                    machine.save.end (result);
                } catch (GLib.Error e) {
                    window.notificationbar.display_error (_("Pausing “%s” failed").printf (machine.name));
                }
            });
        }

        pause_btn.sensitive = false;
        window.selection_mode = false;
    }

    [GtkCallback]
    private void on_open_btn_clicked () {
        App.app.open_selected_items_in_new_window ();
    }

    [GtkCallback]
    private void on_remove_btn_clicked () {
        App.app.remove_selected_items ();
    }

    private void update_favorite_btn () {
        var active = false;
        var sensitive = App.app.selected_items.length () > 0;

        foreach (var item in App.app.selected_items) {
            var machine = item as Machine;
            if (machine == null)
                continue;

            var is_favorite = "favorite" in machine.config.categories;
            if (!active) {
                active = is_favorite;
            } else if (!is_favorite) {
                sensitive = false;
                break;
            }
        }

        ignore_favorite_btn_clicks = true;
        favorite_btn.active = active;
        favorite_btn.sensitive = sensitive;
        ignore_favorite_btn_clicks = false;
    }

    private void update_pause_btn () {
        var sensitive = false;
        foreach (var item in App.app.selected_items) {
            if (!(item is Machine))
                continue;

            var machine = item as Machine;
            if (machine.can_save && machine.is_running) {
                sensitive = true;

                break;
            }
        }

        pause_btn.sensitive = sensitive;
    }

    private void update_delete_btn () {
        App.app.collection.foreach_item ((item) => {
            var can_delete_id = item.get_data<ulong> ("can_delete_id");
            if (can_delete_id > 0) {
                    item.disconnect (can_delete_id);
                    item.set_data<ulong> ("can_delete_id", 0);
            }
        });

        var sensitive = App.app.selected_items.length () > 0;
        foreach (var item in App.app.selected_items) {
            ulong can_delete_id = 0;
            can_delete_id = item.notify["can-delete"].connect (() => {
                update_delete_btn ();
            });
            item.set_data<ulong> ("can_delete_id", can_delete_id);

            if (item is Machine) {
                var machine = item as Machine;
                if (!machine.can_delete) {
                    sensitive = false;
                    break;
                }
            }
        }

        remove_btn.sensitive = sensitive;
    }

    private void update_open_btn () {
        App.app.collection.foreach_item ((item) => {
            var importing_id = item.get_data<ulong> ("importing_id");
            if (importing_id > 0) {
                item.disconnect (importing_id);
                item.set_data<ulong> ("importing_id", 0);
            }
        });

        var items = App.app.selected_items.length ();
        var sensitive = items > 0;
        foreach (var item in App.app.selected_items) {
            ulong importing_id = 0;
            importing_id = item.notify["importing"].connect (() => {
                update_open_btn ();
            });
            item.set_data<ulong> ("importing_id", importing_id);

            if (item is LibvirtMachine) {
                var libvirt_machine = item as LibvirtMachine;
                if (libvirt_machine.importing) {
                    sensitive = false;
                    break;
                }
            }
        }
        open_btn.sensitive = sensitive;

        if (items == 0)
            // Translators: This is a button to open box(es) in new window(s)
            open_btn.label = C_("0 items selected", "_Open in new window");
        else
            open_btn.label = ngettext ("_Open in new window", "_Open in %u new windows", items).printf (items);
    }
}
