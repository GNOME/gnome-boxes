// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/remote-connection.ui")]
private class Boxes.RemoteConnectionAssistant : Gtk.Dialog {
    [GtkChild]
    private Gtk.Entry url_entry;

    [GtkChild]
    private Gtk.Button connect_button;

    private AppWindow app_window;

    construct {
        use_header_bar = 1;
    }

    public RemoteConnectionAssistant (AppWindow app_window, string? uri = null) {
        this.app_window = app_window;

        set_transient_for (app_window);

        url_entry.changed.connect (on_url_entry_changed);
        connect_button.clicked.connect (on_connect_button_clicked);
        connect_button.get_style_context ().add_class ("suggested-action");

        url_entry.set_text (uri);
    }

    private void on_url_entry_changed () {
        if (url_entry.text == "") {
            connect_button.sensitive = false;

            return;
        }

        var uri = Xml.URI.parse (url_entry.text);
        if (uri == null || uri.scheme == null) {
            connect_button.sensitive = false;

            return;
        }

        if (uri.scheme == "vnc" ||
            uri.scheme == "ssh" ||
            uri.scheme == "rdp" ||
            uri.scheme == "spice") {
            connect_button.sensitive = true;
        }
    }

    [GtkCallback]
    private void on_url_entry_activated () {
        if (connect_button.sensitive)
            on_connect_button_clicked ();
    }

    private void on_connect_button_clicked () {
        var uri = Xml.URI.parse (url_entry.text);
        var source = new CollectionSource (uri.server ?? url_entry.text, uri.scheme, url_entry.text);

        try {
            if (source != null) {
                var machine = new RemoteMachine (source);
                if (machine is RemoteMachine)
                    App.app.add_collection_source.begin (source);

                app_window.connect_to (machine);
            }

            destroy ();
        } catch (GLib.Error error) {
            warning (error.message);
        }
    }
}
