// This file is part of GNOME Boxes. License: LGPLv2+

// too bad we can't make it just a mixin
public class Boxes.DisplayProperties: GLib.Object {
    private int64 started_time;
    protected void access_start () {
        if (started_time != 0)
            return;

        started_time = get_monotonic_time ();
        config.access_last_time = get_real_time ();
        config.access_ntimes += 1;

        if (config.access_first_time == 0)
            config.access_first_time = config.access_last_time;
    }

    protected void access_finish () {
        if (started_time == 0)
            return;

        var duration = get_monotonic_time () - started_time;
        duration /= 1000000; // convert to seconds
        config.access_total_time += duration;

        started_time = 0;
    }

    ~DisplayProperties () {
        access_finish ();
    }

    public BoxConfig? config { get; set; }
}
