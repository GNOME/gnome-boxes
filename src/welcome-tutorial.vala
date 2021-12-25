// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Hdy;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/welcome-tutorial.ui")]
private class Boxes.WelcomeTutorial : Gtk.Dialog {
    [GtkChild]
    private unowned Box inner_box;
    [GtkChild]
    private unowned Carousel paginator;
    [GtkChild]
    private unowned Button go_back_button;
    [GtkChild]
    private unowned Button go_next_button;

    private GLib.List<unowned WelcomeTutorialPage> pages;
    private CssProvider provider;

    construct {
        use_header_bar = 1;

        pages = new GLib.List<unowned WelcomeTutorialPage> ();
        foreach (var page in paginator.get_children ()) {
            assert (page is WelcomeTutorialPage);
            pages.append (page as WelcomeTutorialPage);
        }

        provider = new CssProvider ();
        inner_box.get_style_context ().add_provider (provider,
                                                     STYLE_PROVIDER_PRIORITY_APPLICATION);

        on_position_changed ();
    }

    public WelcomeTutorial (AppWindow app_window) {
        set_transient_for (app_window);
    }

    private void set_background_color (Gdk.RGBA color) {
        var css = """
          .welcome-tutorial {
            background-color: %s;
          }
        """.printf (color.to_string ());

        try {
            provider.load_from_data (css);
        } catch (GLib.Error error) {
            warning ("Failed to load css for setting background color: %s", error.message);
        }
    }

    [GtkCallback]
    private void on_position_changed () {
        var n_pages = pages.length ();
        var position = paginator.position;

        // Toggle button's visibility
        go_back_button.opacity = double.min (position, 1);
        go_next_button.opacity = double.max (0, n_pages - 1 - position);

        var color1 = pages.nth_data ((uint) Math.floor (position)).color;
        var color2 = pages.nth_data ((uint) Math.ceil (position)).color;
        var progress = position % 1;

        Gdk.RGBA rgba = {
            red:   color1.red   * (1 - progress) + color2.red   * progress,
            green: color1.green * (1 - progress) + color2.green * progress,
            blue:  color1.blue  * (1 - progress) + color2.blue  * progress,
            alpha: 1
        };
        set_background_color (rgba);
    }

    [GtkCallback]
    private void on_next_button_clicked () {
        var index = (int) Math.round (paginator.position) + 1;
        if (index >= pages.length ())
            return;

        paginator.scroll_to (pages.nth_data (index));

    }

    [GtkCallback]
    private void on_back_button_clicked () {
        var index = (int) Math.round (paginator.position) - 1;
        if (index < 0)
            return;

        paginator.scroll_to (pages.nth_data (index));
    }
}
