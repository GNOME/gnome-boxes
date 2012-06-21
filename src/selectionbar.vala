// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gtk;

private class Boxes.Selectionbar: GLib.Object {
    public Clutter.Actor actor { get { return gtk_actor; } }
    public static const float spacing = 60.0f;

    private GtkClutter.Actor gtk_actor;
    private Gtk.Toolbar toolbar;
    private Gtk.ToggleToolButton favorite_btn;
    private Gtk.ToggleToolButton remove_btn;

    public Selectionbar () {
        toolbar = new Gtk.Toolbar ();
        toolbar.show_arrow = false;
        toolbar.icon_size = Gtk.IconSize.LARGE_TOOLBAR;

        var bin = new Gtk.Alignment (0,0,1,1);
        draw_as_css_box (bin);
        bin.add (toolbar);
        bin.get_style_context ().add_class ("selectionbar");

        gtk_actor = new GtkClutter.Actor.with_contents (bin);
        gtk_actor.opacity = 0;

        favorite_btn = new Gtk.ToggleToolButton ();
        toolbar.insert (favorite_btn, 0);
        favorite_btn.icon_name = "emblem-favorite-symbolic";
        favorite_btn.clicked.connect (() => {
           foreach (var item in App.app.selected_items) {
               var machine = item as Machine;
               if (machine != null)
                   machine.config.add_category ("favourite");
           }
        });

        var separator = new Gtk.SeparatorToolItem();
        toolbar.insert(separator, 1);

        remove_btn = new Gtk.ToggleToolButton ();
        toolbar.insert (remove_btn, 2);
        remove_btn.icon_name = "edit-delete-symbolic";
        remove_btn.clicked.connect (() => {
            App.app.remove_selected_items ();
        });
        toolbar.show_all ();

        actor.reactive = true;

        App.app.notify["selection-mode"].connect (() => {
            update_visible ();
        });

        App.app.notify["selected-items"].connect (() => {
            update_visible ();
        });
    }

    private void update_visible () {
        if (!App.app.selection_mode)
            visible = false;
        else
            visible = App.app.selected_items.length () > 0;
    }

    private bool visible {
        set {
            fade_actor (actor, value ? 255 : 0);
        }
    }
}
