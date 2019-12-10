// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/welcome-tutorial-page.ui")]
private class Boxes.WelcomeTutorialPage : Gtk.Box {
    [GtkChild]
    private Label title_label;
    [GtkChild]
    private Label description_label;

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

    public string color { set; get; }
    public string image { set; get; }

    [GtkCallback]
    private void load_css () {
        var provider = new CssProvider ();
        var css = """
          .tutorial-page {
            background-color: #%s;
            background-image: url("resource://%s");
          }
        """.printf (color, image);

        provider.load_from_data (css);
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (),
                                                  provider,
                                                  STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
}
