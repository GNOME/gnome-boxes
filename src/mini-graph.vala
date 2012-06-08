// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.MiniGraph: Gtk.DrawingArea {
    private double[] _points;
    public double[] points { get { return _points; }
        set {
            _points = value;
            queue_draw ();
        }
    }
    public int npoints { get; set; default = -1; }

    private double _ymax;
    private double ymax { get { return _ymax; }
        set {
            _ymax = value;
            ymax_set = true;
        }
    }
    private bool ymax_set = false;

    public MiniGraph (double[] points = {}, int npoints = -1) {
        this.points = points;
        this.npoints = npoints;
    }

    public MiniGraph.with_ymax (double[] points, double ymax, int npoints = -1) {
        this.points = points;
        this.ymax = ymax;
        this.npoints = npoints;
    }

    private double max () {
        if (points.length == 0)
            return 1.0;

        double max = points[0];
        foreach (var p in points) {
            if (p > max)
                max = p;
        }

        return max;
    }

    public override bool draw (Cairo.Context cr) {
        var width = get_allocated_width ();
        var height = get_allocated_height ();
        var style = get_style_context ();

        Gdk.cairo_set_source_rgba (cr, style.get_background_color (get_state_flags ()));
        cr.rectangle (0, 0, width, height);
        cr.fill ();

        var nstep = (npoints == -1 ? points.length : npoints) - 1;
        var ymax = ymax_set ? ymax : max ();
        var dy = 0.0;
        var dx = 0.0;
        if (nstep != 0)
            dx = (double)width / nstep;
        if (ymax != 0)
            dy = (double)height / ymax;

        Gdk.cairo_set_source_rgba (cr, style.get_color (Gtk.StateFlags.NORMAL));
        var x = 0.0;
        foreach (var p in points) {
            var y = height - p * dy;
            if (x == 0.0)
                cr.move_to (x, y);
            else
                cr.line_to (x, y);
            x += dx;
        }
        cr.line_to (x - dx, height);
        cr.line_to (0, height);
        cr.fill ();

        Gdk.cairo_set_source_rgba (cr, style.get_border_color (get_state_flags ()));
        cr.set_line_width (1.0);
		x = 0.0;
        foreach (var p in points) {
            var y = height - p * dy;

            if (x == 0.0)
                cr.move_to (x, y);
            else
                cr.line_to (x, y);
            x += dx;
        }
        cr.stroke ();

        return true;
    }
} 
