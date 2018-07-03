// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Vte;

private class Boxes.DockerDisplay: Boxes.Display {
    public override string protocol { get { return "DOCKER"; } }
    public override string? uri { owned get { return @"docker://$host"; } }
    private Terminal display;
    private string host;
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

    public DockerDisplay (BoxConfig config, string host, int port) {
        this.config = config;

        this.host = host;

        config.save_properties (display, saved_properties);
    }

    public DockerDisplay.with_uri (BoxConfig config, string _uri) throws Boxes.Error {
        this.config = config;

        var uri = Xml.URI.parse (_uri);

        if (uri.scheme != "docker")
            throw new Boxes.Error.INVALID ("the URL is not docker://");

        if (uri.server == null)
            throw new Boxes.Error.INVALID ("the URL is missing a server");

	this.host = uri.server + uri.path;

        config.save_properties (display, saved_properties);
    }

    public override Gtk.Widget get_display (int n) {
        return display;
    }

    public override void set_enable_audio (bool enable) {
    }

    public override Gdk.Pixbuf? get_pixbuf (int n) throws Boxes.Error {
	return null;
    }

    private bool run (string [] command) {
        if (!connected)
            return false;

	SpawnFlags flags = SpawnFlags.SEARCH_PATH_FROM_ENVP | SpawnFlags.DO_NOT_REAP_CHILD;

	return display.spawn_sync (PtyFlags.DEFAULT, Environment.get_home_dir (), command, null, flags, null, null);
    }

    public override void connect_it (owned Display.OpenFDFunc? open_fd = null) throws GLib.Error {
        // We only initiate connection once
        if (connected)
            return;
        connected = true;
	
	display.show_all ();

	string[] docker_pull = {
            "/usr/bin/docker", "pull " + host,
        };

	string[] docker_run = {
	    "/usr/bin/docker", "run", "-it", host,
	};

	run (docker_pull);
	run (docker_run);
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
