// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/welcome-tutorial.ui")]
private class Boxes.WelcomeTutorial : Gtk.Dialog {
    [GtkChild]
    private Stack stack;
    [GtkChild]
    private Button go_back_button;
    [GtkChild]
    private Button go_next_button;

    private GLib.List<unowned Widget> pages;

    private uint _visible_page_idx = 0;
    private uint visible_page_idx {
        set {
            _visible_page_idx = value;

            stack.set_visible_child (pages.nth_data (visible_page_idx));
        }
        get {
            return _visible_page_idx;
        }
    }

    construct {
        use_header_bar = 1;

        pages = stack.get_children ();

        on_stack_page_changed ();
    }

    public WelcomeTutorial (AppWindow app_window) {
        set_transient_for (app_window);
    }

    [GtkCallback]
    private void on_stack_page_changed () {
        var n_pages = pages.length ();

        var topbar = get_header_bar () as Gtk.HeaderBar;
        topbar.subtitle = _("%u/%u").printf (visible_page_idx + 1, n_pages);

        // Toggle button's visibility
        go_back_button.visible = (visible_page_idx > 0);
        go_next_button.visible = (visible_page_idx < pages.length () - 1);

    }

    [GtkCallback]
    private void on_next_button_clicked () {
        visible_page_idx += 1;

    }

    [GtkCallback]
    private void on_back_button_clicked () {
        visible_page_idx -= 1;
    }
}
