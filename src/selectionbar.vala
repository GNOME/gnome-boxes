// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gtk;

private class Boxes.Selectionbar: Gtk.Revealer {
    private Gtk.HeaderBar headerbar;
    private Gtk.ToggleButton favorite_btn;
    private Gtk.Button pause_btn;
    private Gtk.Button remove_btn;
    private Gtk.Button properties_btn;

    public Selectionbar () {
        transition_type = Gtk.RevealerTransitionType.SLIDE_UP;

        headerbar = new Gtk.HeaderBar ();
        add (headerbar);

        favorite_btn = new Gtk.ToggleButton ();
        headerbar.pack_start (favorite_btn);
        favorite_btn.image = new Gtk.Image.from_icon_name ("emblem-favorite-symbolic", Gtk.IconSize.MENU);
        favorite_btn.clicked.connect (() => {
           foreach (var item in App.app.selected_items) {
               var machine = item as Machine;
               if (machine == null)
                   continue;
               machine.config.set_category ("favorite", favorite_btn.active);
           }

           App.app.selection_mode = false;
        });

        pause_btn = new Gtk.Button ();
        headerbar.pack_start (pause_btn);
        pause_btn.image = new Gtk.Image.from_icon_name ("media-playback-pause-symbolic", Gtk.IconSize.MENU);
        pause_btn.clicked.connect (() => {
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
        });

        remove_btn = new Gtk.Button.from_stock (Gtk.Stock.DELETE);
        headerbar.pack_start (remove_btn);
        remove_btn.clicked.connect (() => {
            App.app.remove_selected_items ();
        });

        properties_btn = new Gtk.Button.from_stock (Gtk.Stock.PROPERTIES);
        headerbar.pack_end (properties_btn);
        properties_btn.clicked.connect (() => {
            App.app.show_properties ();
        });

        show_all ();

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

        favorite_btn.active = active;
        favorite_btn.sensitive = sensitive;
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
