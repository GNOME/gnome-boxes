// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Vte;

private class Boxes.SshDisplay: Boxes.Display {
    public override string protocol { get { return "SSH"; } }
    public override string? uri { owned get { return @"ssh://$user@$host"; } }
    private Terminal display;
    private string host;
    private string user = "";
    private int port;
    private BoxConfig.SavedProperty[] saved_properties;

    construct {
        saved_properties = {
            BoxConfig.SavedProperty () { name = "read-only", default_value = false }
        };
        display = new Terminal ();
        display.show.connect (() => {
            show (0);
            access_start ();
        });
    }

    public SshDisplay (BoxConfig config, string host, int port, string user = "") {
        this.config = config;

        this.user = user;
        this.host = host;
        this.port = port;

        config.save_properties (display, saved_properties);
    }

    public SshDisplay.with_uri (BoxConfig config, string _uri) throws Boxes.Error {
        this.config = config;

        var uri = Xml.URI.parse (_uri);
        if (uri.scheme != "ssh")
            throw new Boxes.Error.INVALID ("the URL is not ssh://");

        if (uri.server == null)
            throw new Boxes.Error.INVALID ("the URL is missing a server");

        this.host = uri.server + uri.path;
        this.user = uri.user;
        this.port = uri.port <= 0 ? 22 : uri.port;

        config.save_properties (display, saved_properties);
    }

    public override Gtk.Widget get_display (int n) {
        return display;
    }

    public override void set_enable_audio (bool enable) {
    }

    public override Gdk.Pixbuf? get_pixbuf (int n) {
        return null;
    }

    private bool run (string[] command) {
        SpawnFlags flags = SpawnFlags.SEARCH_PATH_FROM_ENVP | SpawnFlags.DO_NOT_REAP_CHILD;

        return display.spawn_sync (PtyFlags.DEFAULT, Environment.get_home_dir (), command, null, flags, null, null);
    }

    public override void connect_it (owned Display.OpenFDFunc? open_fd = null) {
        // We only initiate connection once
        if (connected)
            return;
        connected = true;

        display.show_all ();

        var prefix = this.user != "" ? this.user + "@" : "";
        string[] ssh_connect_cmd = {
            "ssh", @"-p $port", prefix + this.host,
        };

        run (ssh_connect_cmd);
    }

    public override void disconnect_it () {
    }

    public override List<Boxes.Property> get_properties (Boxes.PropertiesPage page) {
        var list = new List<Boxes.Property> ();

        return list;
    }

    public override void send_keys (uint[] keyvals) {
    }
}
