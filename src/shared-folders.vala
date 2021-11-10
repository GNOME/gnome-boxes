// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.SharedFolder: Boxes.CollectionItem {
    public string path { set; get; }
    public string machine_uuid { set; get; }

    public SharedFolder (string machine_uuid, string path, string name = "") {
        this.machine_uuid = machine_uuid;
        this.path = path;
        this.name = name;
    }
}

private class Boxes.SharedFoldersManager: Boxes.Collection {
    private static SharedFoldersManager shared_folders_manager;

    private HashTable<string, GLib.ListStore> folders = new HashTable <string, GLib.ListStore> (str_hash, str_equal);

    private GLib.Settings settings = new GLib.Settings ("org.gnome.boxes");

    public static SharedFoldersManager get_default () {
        if (shared_folders_manager == null)
            shared_folders_manager = new SharedFoldersManager ();

        return shared_folders_manager;
    }

    construct {
        string serialized_list = settings.get_string ("shared-folders");
        if (serialized_list == "")
            return;

        try {
            GLib.Variant? entry = null;
            string uuid, path, name;

            var variant = Variant.parse (new GLib.VariantType.array (GLib.VariantType.VARIANT), serialized_list);
            VariantIter iter = variant.iterator ();
            while (iter.next ("v",  &entry)) {
                entry.lookup ("uuid", "s", out uuid);
                entry.lookup ("path", "s", out path);
                entry.lookup ("name", "s", out name);

                add_item (new SharedFolder (uuid, path, name));
            }

        } catch (VariantParseError err) {
            warning (err.message);
        }
    }

    public GLib.ListStore get_folders (string machine_uuid) {
        var store = folders.get (machine_uuid);
        if (store == null) {
            store = new GLib.ListStore (typeof (SharedFolder));

            folders[machine_uuid] = store;
        }

        return store;
    }

    public new bool add_item (SharedFolder folder) {
        var model = get_folders (folder.machine_uuid);
        model.append (folder);

        var shared_folder = get_shared_folder_real_path (folder);
        if (!FileUtils.test (shared_folder, FileTest.IS_DIR))
            Posix.unlink (folder.path);

        if (!FileUtils.test (shared_folder, FileTest.EXISTS)) {
            if (Posix.mkdir (shared_folder, 0755) == -1) {
                warning (strerror (errno));

                return false;
            }
        }

        var link_path = GLib.Path.build_filename (shared_folder, folder.name);
        if (GLib.FileUtils.symlink (folder.path, link_path) == -1) {
            debug ("Not creating symlink for shared folder \"%s\": %s", link_path, strerror (errno));

            return false;
        }

        return add_to_gsetting (folder);
    }

    private bool add_to_gsetting (SharedFolder folder) {
        var variant_builder = new GLib.VariantBuilder (new GLib.VariantType.array (VariantType.VARIANT));
        string shared_folders = settings.get_string ("shared-folders");
        if (shared_folders != "") {
            try {
                GLib.Variant? entry = null;

                var variant = Variant.parse (new GLib.VariantType.array (GLib.VariantType.VARIANT), shared_folders);
                VariantIter iter = variant.iterator ();
                while (iter.next ("v",  &entry)) {
                    variant_builder.add ("v",  entry);
                }
            } catch (VariantParseError err) {
                warning (err.message);
            }
        }

        var entry_variant_builder = new GLib.VariantBuilder (GLib.VariantType.VARDICT);

        var uuid_variant = new GLib.Variant ("s", folder.machine_uuid);
        var path_variant = new GLib.Variant ("s", folder.path);
        var name_variant = new GLib.Variant ("s", folder.name);
        entry_variant_builder.add ("{sv}", "uuid", uuid_variant);
        entry_variant_builder.add ("{sv}", "path", path_variant);
        entry_variant_builder.add ("{sv}", "name", name_variant);
        var entry_variant = entry_variant_builder.end ();

        variant_builder.add ("v",  entry_variant);
        var variant = variant_builder.end ();

        return settings.set_string ("shared-folders", variant.print (true));
    }

    public new void remove_item (SharedFolder folder) {
        var list_model = folders.get (folder.machine_uuid);
        for (var idx = 0; idx < list_model.get_n_items (); idx++) {
            var item = list_model.get_item (idx) as SharedFolder;
            if (item.name == folder.name) {
                list_model.remove (idx);

                break;
            }
        }

        var shared_folder = get_shared_folder_real_path (folder);
        if (!FileUtils.test (shared_folder, FileTest.EXISTS) || !FileUtils.test (shared_folder, FileTest.IS_DIR))
            return;

        var to_remove = GLib.Path.build_filename (shared_folder, folder.name);
        Posix.unlink (to_remove);

        remove_from_gsetting (folder);
    }

    private void remove_from_gsetting (SharedFolder folder) {
        var variant_builder = new GLib.VariantBuilder (new GLib.VariantType.array (VariantType.VARIANT));

        string shared_folders = settings.get_string ("shared-folders");
        if (shared_folders == "")
            return;

        try {
            GLib.Variant? entry = null;
            string name_str;
            string uuid_str;

            var variant = Variant.parse (new GLib.VariantType.array (GLib.VariantType.VARIANT), shared_folders);
            VariantIter iter = variant.iterator ();
            while (iter.next ("v",  &entry)) {
                entry.lookup ("uuid", "s", out uuid_str);
                entry.lookup ("name", "s", out name_str);

                if (uuid_str == folder.machine_uuid && name_str == folder.name)
                    continue;

                variant_builder.add ("v", entry);
            }
            variant = variant_builder.end ();

            settings.set_string ("shared-folders", variant.print (true));
        } catch (VariantParseError err) {
            warning (err.message);
        }

    }

    private static string get_shared_folder_real_path (SharedFolder folder) {
        return GLib.Path.build_filename (GLib.Environment.get_user_config_dir (),
                                         Config.PACKAGE_TARNAME,
                                         folder.machine_uuid);
    }
}
