// This file is part of GNOME Boxes. License: LGPLv2
using Config;
using Posix;

// FIXME: vala includes header incorrectly, this will make sure config.h comes on top...
static const string foo_ = GNOMELOCALEDIR;

private static bool version;

private const OptionEntry[] options = {
    { "version", 0, 0, OptionArg.NONE, ref version, N_("Display version number"), null },
    { null }
};

private static void parse_args (ref unowned string[] args) {
    var parameter_string = _("- A simple application to access remote or virtual machines");
    var opt_context = new OptionContext (parameter_string);
    opt_context.set_help_enabled (true);
    opt_context.set_ignore_unknown_options (true);
    opt_context.add_main_entries (options, null);
    opt_context.add_group (Gtk.get_option_group (true));
    opt_context.add_group (Cogl.get_option_group ());
    opt_context.add_group (Clutter.get_option_group_without_init ());
    opt_context.add_group (GtkClutter.get_option_group ());
    // FIXME: add spice

    try {
        opt_context.parse (ref args);
    } catch (OptionError.BAD_VALUE err) {
        GLib.stdout.printf (opt_context.get_help (true, null));
        exit (1);
    } catch (OptionError e) {
        warning (e.message);
    }

    if (version) {
        GLib.stdout.printf ("%s\n", Config.BUILD_VERSION);
        exit (0);
    }
}

public void main (string[] args) {
    Intl.bindtextdomain (GETTEXT_PACKAGE, GNOMELOCALEDIR);
    Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (GETTEXT_PACKAGE);
    GLib.Environment.set_application_name (_("GNOME Boxes"));

    parse_args (ref args);

    Gtk.Window.set_default_icon_name ("gnome-boxes");
    Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;
    var provider = new Gtk.CssProvider ();
    try {
        var sheet = Boxes.get_style ("gtk-style.css");
        provider.load_from_path (sheet);
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (),
                                                  provider,
                                                  600);
    } catch (GLib.Error e) {
        warning (e.message);
    }

    new Boxes.App ();
    Gtk.main ();
}

