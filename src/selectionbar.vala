// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/selectionbar.ui")]
private class Boxes.Selectionbar: Gtk.Revealer {
    [GtkChild]
    private Gtk.ToggleButton favorite_btn;
    [GtkChild]
    private Gtk.Button pause_btn;
    [GtkChild]
    private Gtk.Button remove_btn;
    [GtkChild]
    private Gtk.Button properties_btn;

    public Selectionbar () {
        App.app.notify["selection-mode"].connect (() => {
            reveal_child = App.app.selection_mode;
        });

        App.app.notify["selected-items"].connect (() => {
            update_favorite_btn ();
            update_properties_btn ();
            update_pause_btn ();
            update_delete_btn ();
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

        App.app.selection_mode = false;
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
                    App.app.notificationbar.display_error (_("Pausing '%s' failed").printf (machine.name));
                }
            });
        }

        pause_btn.sensitive = false;
        App.app.selection_mode = false;
    }

    [GtkCallback]
    private void on_remove_btn_clicked () {
        App.app.remove_selected_items ();
    }

    [GtkCallback]
    private void on_properties_btn_clicked () {
        App.app.show_properties ();
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

    private void update_properties_btn () {
        var sensitive = App.app.selected_items.length () == 1;

        properties_btn.sensitive = sensitive;
    }

    private void update_pause_btn () {
        var sensitive = false;
        foreach (var item in App.app.selected_items) {
            if (!(item is Machine))
                continue;

            var machine = item as Machine;
            if (machine.can_save && machine.state != Machine.MachineState.SAVED) {
                sensitive = true;

                break;
            }
        }

        pause_btn.sensitive = sensitive;
    }

    private void update_delete_btn () {
        foreach (var item in App.app.collection.items.data) {
            var can_delete_id = item.get_data<ulong> ("can_delete_id");
            if (can_delete_id > 0) {
                    item.disconnect (can_delete_id);
                    item.set_data<ulong> ("can_delete_id", 0);
            }
        }

        var sensitive = App.app.selected_items.length () > 0;
        foreach (var item in App.app.selected_items) {
            ulong can_delete_id = 0;
            can_delete_id = item.notify["can-delete"].connect (() => {
                update_delete_btn ();
            });
            item.set_data<ulong> ("can_delete_id", can_delete_id);

            if (item is Machine && !(item as Machine).can_delete) {
                sensitive = false;
                break;
            }
        }

        remove_btn.sensitive = sensitive;
    }
}
