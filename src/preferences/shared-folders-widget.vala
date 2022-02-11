// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/shared-folder-row.ui")]
private class Boxes.SharedFolderRow : Hdy.ActionRow {
    public signal void removed (SharedFolder folder);

    public SharedFolder folder { get; private set; }

    public SharedFolderRow (SharedFolder folder) {
        this.folder = folder;

        folder.bind_property ("path", this, "title", BindingFlags.SYNC_CREATE);
        folder.bind_property ("name", this, "subtitle", BindingFlags.SYNC_CREATE);
    }

    [GtkCallback]
    private void on_delete_button_clicked () {
        removed (folder);
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/shared-folders-widget.ui")]
private class Boxes.SharedFoldersWidget: Hdy.PreferencesGroup {
    private string machine_uuid;

    private SharedFoldersManager manager = SharedFoldersManager.get_default ();

    private GLib.ListStore list_model;

    private Boxes.SharedFolderPopover popover;

    [GtkChild]
    private unowned Gtk.ListBox listbox;

    construct {
        popover = new SharedFolderPopover ();
        popover.saved.connect (on_popover_saved);
    }

    public void setup (string machine_uuid) {
        this.machine_uuid = machine_uuid;

        list_model = manager.get_folders (machine_uuid);
        list_model.items_changed.connect (on_list_updated);
        listbox.bind_model (list_model, create_shared_folder_row);

        var add_button = new Gtk.MenuButton () {
            visible = true,
            image = new Gtk.Image () {
                icon_name = "list-add-symbolic"
            },
            popover = popover
        }; 
        add_button.get_style_context ().add_class ("flat");
        listbox.add (add_button);

        on_list_updated ();
    }

    private bool on_popover_saved (string path, string? name) {
        return manager.add_item (new SharedFolder (machine_uuid, path, name));
    }

    private Gtk.Widget create_shared_folder_row (Object item) {
        var folder = item as SharedFolder;
        var row = new SharedFolderRow (folder);

        row.removed.connect (manager.remove_item);

        return row;
    }

    private void on_list_updated () {
        if (list_model.get_n_items () == 0) {
            // Translators: "spice-webdav" is a name and shouldn't be translated. %s is an URL.
            description = _("Use the button below to add your first shared folder. For file sharing to work, the guest box needs to have <a href='%s'>spice-webdav</a> installed.").printf ("https://www.spice-space.org/download.html");
        } else {
            description = null;
        }
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/shared-folder-popover.ui")]
private class Boxes.SharedFolderPopover: Gtk.Popover {
    public signal bool saved (string path, string name);

    [GtkChild]
    public unowned Gtk.FileChooserButton file_chooser_button;
    [GtkChild]
    public unowned Gtk.Entry name_entry;

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
        var uri = file_chooser_button.get_uri ();
        File file = File.new_for_uri (uri);
        var name = name_entry.get_text ();

        if (uri != null) {
            if (name == "")
                name = file.get_basename ();

            saved (file.get_path (), name);
        }

        popdown ();
    }
}
