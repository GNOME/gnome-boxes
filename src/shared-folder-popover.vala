// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/shared-folder-popover.ui")]
private class Boxes.SharedFolderPopover: Gtk.Popover {
    public signal void saved (string local_folder, string name, int target_position);

    public Gtk.FileChooserNative file_chooser;

    [GtkChild]
    public Gtk.Entry name_entry;
    [GtkChild]
    public Gtk.Entry path_entry;

    public int target_position;

    construct {
        file_chooser = new Gtk.FileChooserNative (
            _("Select Shared Folder"),
            App.app.main_window,
            Gtk.FileChooserAction.SELECT_FOLDER,
            _("Select"), _("Cancel")
        );
    }

    [GtkCallback]
    public void on_cancel (Gtk.Button cancel_button) {
        popdown ();
    }

    [GtkCallback]
    private void on_closed () {
        name_entry.set_text ("");
        path_entry.set_text ("");
    }

    [GtkCallback]
    public void on_save (Gtk.Button save_button) {
        var uri = path_entry.get_text ();
        File file = File.new_for_uri (uri);
        var name = name_entry.get_text ();

        if (uri != null) {
            if (name == "")
                name = file.get_basename ();

            saved (file.get_path (), name, target_position);
        }

        popdown ();
    }

    [GtkCallback]
    public void on_browse_button_clicked () {
        if (file_chooser.run () == Gtk.ResponseType.ACCEPT) {
            var uri = file_chooser.get_uri ();
            path_entry.set_text (uri);
        }
    }
}
