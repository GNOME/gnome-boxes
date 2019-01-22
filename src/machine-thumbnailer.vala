// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.MachineThumbnailer: Object {
    private const Gtk.CornerType[] right_corners = { Gtk.CornerType.TOP_RIGHT, Gtk.CornerType.BOTTOM_RIGHT };
    private const Gtk.CornerType[] bottom_corners = { Gtk.CornerType.BOTTOM_LEFT, Gtk.CornerType.BOTTOM_RIGHT };

    public const double FRAME_RADIUS = 2.0;
    public const Gdk.RGBA CENTERED_EMBLEM_COLOR = { 0xbe / 255.0, 0xbe / 255.0, 0xbe / 255.0, 1.0 };
    public const Gdk.RGBA SMALL_EMBLEM_COLOR = { 1.0, 1.0, 1.0, 1.0 };
    public const int EMBLEM_PADDING = 8;

    public weak Machine machine { get; private set; }
    public int width { get; set; }
    public int height { get; set; }
    public int centred_emblem_size { get; set; }
    public int emblem_size { get; set; }
    public Gdk.RGBA border_color { get; set; }
    public Gdk.RGBA background_color { get; set; }

    public Gdk.Pixbuf thumbnail { get; private set; }

    public bool favorite_emblem_enabled { get; set; default = true; }

    public MachineThumbnailer (Machine machine,
                               int width, int height,
                               int centred_emblem_size, int emblem_size) {
        this.machine = machine;
        this.width = width;
        this.height = height;
        this.centred_emblem_size = centred_emblem_size;
        this.emblem_size = emblem_size;
        this.border_color = border_color;
        this.background_color = background_color;

        machine.notify["pixbuf"].connect (() => {
            update_thumbnail ();
        });

        machine.notify["under-construction"].connect (() => {
            update_thumbnail ();
        });

        machine.config.notify["categories"].connect (() => {
            update_thumbnail ();
        });

        notify["width"].connect (update_thumbnail);
        notify["height"].connect (update_thumbnail);
        notify["border-color"].connect (update_thumbnail);
        notify["favorite-emblem-enabled"].connect (update_thumbnail);
        notify["construction-spinner-enabled"].connect (update_thumbnail);

        update_thumbnail ();
    }

    private void update_thumbnail () {
        Gdk.Pixbuf? new_thumbnail = null;

        if (machine.is_stopped)
            new_thumbnail = machine.under_construction ? get_under_construction_thumbnail () :
                                                         get_stopped_thumbnail ();
        else if (machine.pixbuf != null)
            new_thumbnail = machine.pixbuf.scale_simple (width, height, Gdk.InterpType.BILINEAR);

        // Use the default thumbnail if no thumbnail have been chosen
        if (new_thumbnail == null)
            new_thumbnail = get_default_thumbnail ();

        if (favorite_emblem_enabled && "favorite" in machine.config.categories)
            new_thumbnail = add_emblem_icon (new_thumbnail, "starred-symbolic", Gtk.CornerType.BOTTOM_LEFT);

        thumbnail = new_thumbnail;
    }

    private Gdk.Pixbuf? empty_thumbnail;
    private Gdk.Pixbuf get_empty_thumbnail () {
        if (empty_thumbnail != null)
            return empty_thumbnail;

        empty_thumbnail = paint_empty_frame (width, height);

        return empty_thumbnail;
    }

    private Gdk.Pixbuf? default_thumbnail;
    private Gdk.Pixbuf get_default_thumbnail () {
        if (default_thumbnail != null)
            return default_thumbnail;

        var frame = get_empty_thumbnail ();
        default_thumbnail = add_centered_emblem_icon (frame, "computer-symbolic", centred_emblem_size);

        return default_thumbnail;
    }

    private Gdk.Pixbuf? stopped_thumbnail;
    private Gdk.Pixbuf get_stopped_thumbnail () {
        if (stopped_thumbnail != null)
            return stopped_thumbnail;

        var frame = get_empty_thumbnail ();
        stopped_thumbnail = add_centered_emblem_icon (frame, "system-shutdown-symbolic", centred_emblem_size);

        return stopped_thumbnail;
    }

    private Gdk.Pixbuf get_under_construction_thumbnail () {
        // If the machine is being constructed, it will draw a spinner itself, so we only need to draw an empty frame.
        return get_empty_thumbnail ();
    }

    private Gdk.Pixbuf add_centered_emblem_icon (Gdk.Pixbuf pixbuf, string icon_name, int size) {
        Gdk.Pixbuf? emblem = null;

        var theme = Gtk.IconTheme.get_default ();
        try {
            var icon_info = theme.lookup_icon (icon_name, size, Gtk.IconLookupFlags.FORCE_SIZE);
            emblem = icon_info.load_symbolic (CENTERED_EMBLEM_COLOR);
        } catch (GLib.Error error) {
            warning (@"Unable to get icon '$icon_name': $(error.message)");
            return pixbuf;
        }

        if (emblem == null)
            return pixbuf;

        double offset_x = pixbuf.width / 2.0 - emblem.width / 2.0;
        double offset_y = pixbuf.height / 2.0 - emblem.height / 2.0;

        var emblemed = pixbuf.copy ();
        emblem.composite (emblemed, (int) offset_x, (int) offset_y, size, size,
                          offset_x, offset_y, 1.0, 1.0, Gdk.InterpType.BILINEAR, 255);

        return emblemed;
    }


    private Gdk.Pixbuf add_emblem_icon (Gdk.Pixbuf pixbuf, string icon_name, Gtk.CornerType corner_type) {
        Gdk.Pixbuf? emblem = null;

        var theme = Gtk.IconTheme.get_default ();
        try {
            var icon_info = theme.lookup_icon (icon_name, emblem_size, Gtk.IconLookupFlags.FORCE_SIZE);
            emblem = icon_info.load_symbolic (SMALL_EMBLEM_COLOR);
        } catch (GLib.Error error) {
            warning (@"Unable to get icon '$icon_name': $(error.message)");
            return pixbuf;
        }

        if (emblem == null)
            return pixbuf;

        var offset_x = corner_type in right_corners ? pixbuf.width - emblem.width - EMBLEM_PADDING :
                                                      EMBLEM_PADDING;

        var offset_y = corner_type in bottom_corners ? pixbuf.height - emblem.height - EMBLEM_PADDING :
                                                       EMBLEM_PADDING;

        var emblemed = pixbuf.copy ();
        emblem.composite (emblemed, offset_x, offset_y, emblem_size, emblem_size,
                          offset_x, offset_y, 1.0, 1.0, Gdk.InterpType.BILINEAR, 255);

        return emblemed;
    }
}
