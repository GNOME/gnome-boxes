// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gtk;

private class Boxes.Selectionbar: GLib.Object {
    public Clutter.Actor actor { get { return gtk_actor; } }
    public static const int default_toolbar_width = 500;

    private GtkClutter.Actor gtk_actor;
    private Gtk.Toolbar toolbar;
    private Gtk.ToggleButton favorite_btn;
    private Gtk.Button pause_btn;
    private Gtk.ToggleButton remove_btn;
    private Gtk.Button properties_btn;

    public Selectionbar () {
        toolbar = new Gtk.Toolbar ();
        toolbar.show_arrow = false;
        toolbar.icon_size = Gtk.IconSize.LARGE_TOOLBAR;
        toolbar.set_size_request (default_toolbar_width, -1);

        toolbar.get_style_context ().add_class ("osd");

        var leftbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        var leftgroup = new Gtk.ToolItem ();
        leftgroup.add (leftbox);
        toolbar.insert(leftgroup, -1);

        var separator = new Gtk.SeparatorToolItem();
        separator.set_expand (true);
        separator.draw = false;
        toolbar.insert(separator, -1);

        var rightbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        var rightgroup = new Gtk.ToolItem ();
        rightgroup.add (rightbox);
        toolbar.insert(rightgroup, -1);

        gtk_actor = new GtkClutter.Actor.with_contents (toolbar);
        gtk_actor.get_widget ().get_style_context ().add_class ("boxes-bg");
        gtk_actor.opacity = 0;
        gtk_actor.set_margin_bottom (32);
        gtk_actor.x_align = Clutter.ActorAlign.CENTER;
        gtk_actor.y_align = Clutter.ActorAlign.END;

        favorite_btn = new Gtk.ToggleButton ();
        leftbox.add (favorite_btn);
        favorite_btn.image = new Gtk.Image.from_icon_name ("emblem-favorite-symbolic", Gtk.IconSize.MENU);
        favorite_btn.clicked.connect (() => {
           foreach (var item in App.app.selected_items) {
               var machine = item as Machine;
               if (machine == null)
                   continue;
               machine.config.set_category ("favorite", favorite_btn.active);
           }
        });

        pause_btn = new Gtk.Button ();
        leftbox.add (pause_btn);
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
        });

        remove_btn = new Gtk.ToggleButton ();
        rightbox.add (remove_btn);
        remove_btn.image = new Gtk.Image.from_icon_name ("edit-delete-symbolic", Gtk.IconSize.MENU);
        remove_btn.clicked.connect (() => {
            App.app.remove_selected_items ();
        });

        properties_btn = new Gtk.Button ();
        rightbox.add (properties_btn);
        properties_btn.image = new Gtk.Image.from_icon_name ("preferences-system-symbolic", Gtk.IconSize.MENU);
        properties_btn.clicked.connect (() => {
            App.app.show_properties ();
        });

        toolbar.show_all ();

        actor.reactive = true;

        App.app.notify["selection-mode"].connect (() => {
            update_visible ();
        });

        App.app.notify["selected-items"].connect (() => {
            update_visible ();
            update_favorite_btn ();
            update_properties_btn ();
            update_pause_btn ();
        });
    }

    private void update_visible () {
        if (!App.app.selection_mode)
            visible = false;
        else
            visible = App.app.selected_items.length () > 0;
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

    private bool visible {
        set {
            fade_actor (actor, value ? 255 : 0);
        }
    }
}
