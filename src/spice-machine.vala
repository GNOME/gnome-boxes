// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.SpiceMachine: Boxes.Machine {

    public SpiceMachine (CollectionSource source, Boxes.App app) {
        base (source, app, source.name);

        update_screenshot.begin ();
    }

    public override void connect_display () {
        if (_connect_display == true)
            return;

        display = new SpiceDisplay.with_uri (source.uri);
        display.connect_it ();
    }

    public override void disconnect_display () {
        _connect_display = false;

        app.display_page.remove_display ();

        if (display != null) {
            display.disconnect_it ();
            display = null;
        }
    }

    public override string get_screenshot_prefix () {
        return source.filename;
    }

    public override bool is_running () {
        // assume the remote is running for now
        return true;
    }
}
