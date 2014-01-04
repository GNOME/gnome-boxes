// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.EmptyBoxes : GLib.Object, Boxes.UI {
    public Clutter.Actor actor { get { return gtk_actor; } }
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private GtkClutter.Actor gtk_actor;
    private Gtk.Grid grid;

    public EmptyBoxes () {
        grid = new Gtk.Grid ();
        grid.orientation = Gtk.Orientation.HORIZONTAL;
        grid.column_spacing = 12;
        grid.hexpand = true;
        grid.vexpand = true;
        grid.halign = Gtk.Align.CENTER;
        grid.valign = Gtk.Align.CENTER;
        grid.row_homogeneous = true;
        grid.get_style_context ().add_class ("dim-label");

        var image = new Gtk.Image.from_icon_name ("application-x-appliance-symbolic", Gtk.IconSize.DIALOG);
        image.get_style_context ().add_class ("boxes-empty-image");
        image.pixel_size = 96;
        grid.add (image);

        var labels_grid = new Gtk.Grid ();
        labels_grid.orientation = Gtk.Orientation.VERTICAL;
        grid.add (labels_grid);

        var label = new Gtk.Label ("<b><span size=\"large\">" +
                                   _("No boxes found") +
                                   "</span></b>");
        label.use_markup = true;
        label.halign = Gtk.Align.START;
        label.vexpand = true;
        labels_grid.add (label);

        label = new Gtk.Label (_("Create one using the button on the top left."));
        label.get_style_context ().add_class ("boxes-empty-details-label");
        label.halign = Gtk.Align.START;
        label.vexpand = true;
        label.xalign = 0;
        label.max_width_chars = 24;
        label.wrap = true;
        labels_grid.add (label);

        gtk_actor = new GtkClutter.Actor.with_contents (grid);
        gtk_actor.get_widget ().get_style_context ().add_class ("boxes-bg");
        gtk_actor.opacity = 255;
        gtk_actor.x_align = Clutter.ActorAlign.FILL;
        gtk_actor.y_align = Clutter.ActorAlign.FILL;
        gtk_actor.x_expand = true;
        gtk_actor.y_expand = true;

        grid.show_all ();

        App.app.collection.item_added.connect (update_visibility);
        App.app.collection.item_removed.connect (update_visibility);

        notify["ui-state"].connect (update_visibility);
    }

    private void update_visibility () {
        App.app.call_when_ready (() => {
            var visible = ui_state == UIState.COLLECTION && App.app.collection.items.length == 0;
            if (visible != gtk_actor.visible)
                fade_actor (gtk_actor, visible? 255 : 0);
        });
    }
}
