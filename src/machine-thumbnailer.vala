// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.MachineThumbnailer: Object {
    public weak Machine machine { get; private set; }
    public int width { get; set; }
    public int height { get; set; }

    public Gdk.Pixbuf? thumbnail { get; private set; }

    public MachineThumbnailer (Machine machine, int width, int height) {
        this.machine = machine;
        this.width = width;
        this.height = height;

        machine.notify["pixbuf"].connect (() => {
            update_thumbnail ();
        });
        machine.notify["is-stopped"].connect (() => {
            update_thumbnail ();
        });

        notify["width"].connect (update_thumbnail);
        notify["height"].connect (update_thumbnail);

        update_thumbnail ();
    }

    private void update_thumbnail () {
        if (!machine.is_stopped && machine.pixbuf != null)
            thumbnail = machine.pixbuf.scale_simple (width, height, Gdk.InterpType.BILINEAR);
        else
            thumbnail = null;
    }
}
