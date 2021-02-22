// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/welcome-tutorial-page.ui")]
private class Boxes.WelcomeTutorialPage : Gtk.Box {
    [GtkChild]
    private unowned Label title_label;
    [GtkChild]
    private unowned Label description_label;

    public string title {
        set {
            title_label.label = value;
        }
        get {
            return title_label.label;
        }
    }
    public string description {
        set {
            description_label.label = value;
        }
        get {
            return description_label.label;
        }
    }

    public Gdk.RGBA color { set; get; }
    public string image { set; get; }

    [GtkCallback]
    private void load_css () {
        var provider = new CssProvider ();
        var css = """
          .tutorial-page {
            background-image: url("resource://%s");
          }
        """.printf (image);

        try {
            provider.load_from_data (css);
            get_style_context ().add_provider (provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
        } catch (GLib.Error error) {
            warning ("Failed to load CSS: %s", error.message);
        }
    }
}
