// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/shared-folder-popover.ui")]
private class Boxes.SharedFolderPopover: Gtk.Popover {
    public signal void saved (string local_folder, string name, int target_position);

    [GtkChild]
    public Gtk.FileChooserButton file_chooser_button;
    [GtkChild]
    public Gtk.Entry name_entry;

    public int target_position;

    construct {
        var default_path = Environment.get_user_special_dir (UserDirectory.PUBLIC_SHARE);
        file_chooser_button.set_current_folder (default_path);
    }

    [GtkCallback]
    public void on_cancel (Gtk.Button cancel_button) {
        popdown ();
    }

    [GtkCallback]
    public void on_save (Gtk.Button save_button) {
        var path = file_chooser_button.get_uri ();
        var name = name_entry.get_text ();

        if (path != null) {
            path.scanf ("file://%s", path);
            if (name == "")
                name = Path.get_basename (path);

            saved (path, name, target_position);
        }

        popdown ();
    }
}
