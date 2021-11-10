// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private abstract class Boxes.Display: GLib.Object {
    public abstract string protocol { get; }
    public abstract string? uri { owned get; }
    public virtual bool can_transfer_files { get { return false; } }

    public BoxConfig? config { get; protected set; }
    public bool can_grab_mouse { get; protected set; }
    public bool mouse_grabbed { get; protected set; }
    public bool keyboard_grabbed { get; protected set; }
    public bool is_guest_agent_connected { get; protected set; }
    public bool need_password { get; protected set; }
    public bool need_username { get; protected set; }
    public string? password { get; set; }
    public string? username { get; set; }
    public bool connected;

    public signal void show (int display_id);
    public signal void hide (int display_id);
    public signal void disconnected (bool connection_failed);
    public signal void got_error (string message);

    public delegate int OpenFDFunc ();

    public abstract Gtk.Widget get_display (int n);
    public abstract Gdk.Pixbuf? get_pixbuf (int n) throws Boxes.Error;
    public abstract void set_enable_audio (bool enable);

    public virtual bool should_keep_alive () {
        return false;
    }

    public abstract void connect_it (owned OpenFDFunc? open_fd = null) throws GLib.Error;
    public abstract void disconnect_it ();

    public virtual void collect_logs (StringBuilder builder) {
    }
    public virtual void transfer_files (GLib.List<string> uris) {
    }
    public abstract void send_keys (uint[] keyvals);

    protected HashTable<int, Gtk.Widget?> displays;

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

    ~Display () {
        access_finish ();
    }

    construct {
        displays = new HashTable<int, Gtk.Widget> (direct_hash, direct_equal);
    }
}
