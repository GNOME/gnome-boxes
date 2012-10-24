// This file is part of GNOME Boxes. License: LGPLv2+

// too bad we can't make it just a mixin
public class Boxes.DisplayProperties: GLib.Object {
    private int64 started_time;
    protected void access_start () {
        if (started_time != 0)
            return;

        started_time = get_monotonic_time ();
        access_last_time = get_real_time ();
        access_ntimes += 1;

        if (access_first_time == 0)
            access_first_time = access_last_time;
    }

    protected void access_finish () {
        if (started_time == 0)
            return;

        var duration = get_monotonic_time () - started_time;
        duration /= 1000000; // convert to seconds
        access_total_time += duration;

        started_time = 0;
    }

    public int64 access_last_time { set; get; }
    public int64 access_first_time { set; get; }
    public int64 access_total_time { set; get; } // in seconds
    public int64 access_ntimes { set; get; }
    private DisplayConfig.SyncProperty[] access_properties;

    construct {
        access_properties = {
            DisplayConfig.SyncProperty () { name = "access-last-time", default_value = (int64)(-1) },
            DisplayConfig.SyncProperty () { name = "access-first-time", default_value = (int64)(-1) },
            DisplayConfig.SyncProperty () { name = "access-total-time", default_value = (int64)(-1) },
            DisplayConfig.SyncProperty () { name = "access-ntimes", default_value = (uint64)0 }
        };

        config.sync_properties (this, access_properties);
    }

    public DisplayProperties.with_config (DisplayConfig config) {
        this.config = config;

        update_filter_data ();
    }

    ~DisplayProperties () {
        access_finish ();
    }

    public DisplayConfig? config { get; set; }

    private string filter_data;

    private void update_filter_data () {
        var builder = new StringBuilder ();

        if (config.last_seen_name != null) {
            builder.append (canonicalize_for_search (config.last_seen_name));
            builder.append_unichar (' ');
        }

        // add categories, url? other metadata etc..

        filter_data = builder.str;
    }

    public bool contains_strings (string[] strings) {
        foreach (string i in strings) {
            if (! (i in filter_data))
                return false;
        }
        return true;
    }
}
