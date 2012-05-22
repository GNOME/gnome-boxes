// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Config;
using Xml;

public errordomain Boxes.Error {
    INVALID,
    COMMAND_FAILED
}

namespace Boxes {
    // FIXME: Remove these when we can use Vala release that provides binding for gdkkeysyms.h
    public const uint F10_KEY = 0xffc7;
    public const uint F11_KEY = 0xffc8;
    public const uint F12_KEY = 0xffc9;

    public string get_pkgdata (string? file_name = null) {
        return Path.build_filename (DATADIR, Config.PACKAGE_TARNAME, file_name);
    }

    public string get_style (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "style", file_name);
    }

    public string get_pixmap (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "pixmaps", file_name);
    }

    public string get_unattended_dir (string? file_name = null) {
        var dir = Path.build_filename (get_pkgdata (), "unattended");

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public string get_user_unattended_dir (string? file_name = null) {
        var dir = Path.build_filename (get_pkgconfig (), "unattended");

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public string get_pkgdata_source (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "sources", file_name);
    }

    public string get_pkgcache (string? file_name = null) {
        var dir = Path.build_filename (Environment.get_user_cache_dir (), Config.PACKAGE_TARNAME);

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public string get_pkgconfig (string? file_name = null) {
        var dir = Path.build_filename (Environment.get_user_config_dir (), Config.PACKAGE_TARNAME);

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public string get_user_pkgdata (string? file_name = null) {
        var dir = Path.build_filename (Environment.get_user_data_dir (), Config.PACKAGE_TARNAME);

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public bool has_pkgconfig_sources () {
        return FileUtils.test (Path.build_filename (get_pkgconfig (), "sources"), FileTest.IS_DIR);
    }

    public string get_pkgconfig_source (string? file_name = null) {
        var dir = Path.build_filename (get_pkgconfig (), "sources");

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public void ensure_directory (string dir) {
        try {
            var file = GLib.File.new_for_path (dir);
            file.make_directory_with_parents (null);
        } catch (GLib.Error error) {
            if (error is IOError.EXISTS)
                return;
            warning (error.message);
        }
    }

    public Clutter.Color gdk_rgba_to_clutter_color (Gdk.RGBA gdk_rgba) {
        Clutter.Color color = {
            (uint8) (gdk_rgba.red * 255).clamp (0, 255),
            (uint8) (gdk_rgba.green * 255).clamp (0, 255),
            (uint8) (gdk_rgba.blue * 255).clamp (0, 255),
            (uint8) (gdk_rgba.alpha * 255).clamp (0, 255)
        };

        return color;
    }

    public Gdk.RGBA get_boxes_bg_color () {
        var style = new Gtk.StyleContext ();
        var path = new Gtk.WidgetPath ();
        path.append_type (typeof (Gtk.Window));
        style.set_path (path);
        style.add_class ("boxes-bg");
        return style.get_background_color (0);
    }

    public Gdk.Color get_color (string desc) {
        Gdk.Color color;
        Gdk.Color.parse (desc, out color);
        return color;
    }

    public void tree_view_activate_on_single_click (Gtk.TreeView tree_view, bool should_activate) {
        var id = tree_view.get_data<ulong> ("boxes-tree-view-activate");

        if (id != 0 && should_activate == false) {
            tree_view.disconnect (id);
            tree_view.set_data<ulong> ("boxes-tree-view-activate", 0);
        } else if (id == 0 && should_activate) {
            id = tree_view.button_press_event.connect ((w, event) => {
                Gtk.TreePath? path;
                unowned Gtk.TreeViewColumn? column;
                int x, y;

                if (event.button == 1 && event.type == Gdk.EventType.BUTTON_PRESS) {
                    tree_view.get_path_at_pos ((int) event.x, (int) event.y, out path, out column, out x, out y);
                    if (path != null)
                        tree_view.row_activated (path, column);
                }

                return false;
            });
            tree_view.set_data<ulong> ("boxes-tree-view-activate", id);
        }
    }

    public void icon_view_activate_on_single_click (Gtk.IconView icon_view, bool should_activate) {
        var id = icon_view.get_data<ulong> ("boxes-icon-view-activate");

        if (id != 0 && should_activate == false) {
            icon_view.disconnect (id);
            icon_view.set_data<ulong> ("boxes-icon-view-activate", 0);
        } else if (id == 0 && should_activate) {
            id = icon_view.button_press_event.connect ((w, event) => {
                Gtk.TreePath? path;

                if (event.button == 1 && event.type == Gdk.EventType.BUTTON_PRESS) {
                    path = icon_view.get_path_at_pos ((int) event.x, (int) event.y);
                    if (path != null)
                        icon_view.item_activated (path);
                }

                return false;
            });
            icon_view.set_data<ulong> ("boxes-icon-view-activate", id);
        }
    }

    public async void output_stream_write (OutputStream stream, uint8[] buffer) throws GLib.IOError {
        var length = buffer.length;
        ssize_t i = 0;

        while (i < length)
            i += yield stream.write_async (buffer[i:length]);
    }

    public string? extract_xpath (string xmldoc, string xpath, bool required = false) throws Boxes.Error {
        var parser = new ParserCtxt ();
        var doc = parser.read_doc (xmldoc, "doc.xml");

        if (doc == null)
            throw new Boxes.Error.INVALID ("Can't parse XML doc");

        var ctxt = new XPath.Context (doc);
        var obj = ctxt.eval (xpath);
        if (obj == null || obj->stringval == null) {
            if (required)
                throw new Boxes.Error.INVALID ("Failed to extract xpath " + xpath);
            else
                return null;
        }

        if (obj->type != XPath.ObjectType.STRING)
            throw new Boxes.Error.INVALID ("Failed to extract xpath " + xpath);

        return obj->stringval;
    }

    public bool keyfile_save (KeyFile key_file, string file_name, bool overwrite = false) {
        try {
            var file = File.new_for_path (file_name);

            if (file.query_exists ())
                if (!overwrite)
                    return false;
                else
                    file.delete ();

            var stream = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
            stream.put_string (key_file.to_data (null));

            return true;
        } catch (GLib.Error error) {
            warning (error.message);
            return false;
        }
    }

    public string replace_regex (string str, string old, string replacement) {
        try {
            var regex = new GLib.Regex (old);
            return regex.replace_literal (str, -1, 0, replacement);
        } catch (GLib.RegexError error) {
            critical (error.message);
            return str;
        }
    }

    public string make_filename (string name) {
        var filename = replace_regex (name, "[\\\\/:()<>|?*]", "_");

        var tryname = filename;
        for (var i = 0; FileUtils.test (tryname, FileTest.EXISTS); i++) {
            tryname =  "%s-%d".printf (filename, i);
        }

        return tryname;
    }

    public void actor_add (Clutter.Actor actor, Clutter.Container container) {
        if (actor.get_parent () == (Clutter.Actor) container)
            return;

        actor_remove (actor);
        container.add (actor);
    }

    public void actor_remove (Clutter.Actor actor) {
        var container = actor.get_parent () as Clutter.Container;

        if (container == null)
            return;

        container.remove (actor);
    }

    public void actor_pin (Clutter.Actor actor) {
        actor.set_geometry (actor.get_geometry ());
    }

    public void actor_unpin (Clutter.Actor actor) {
        actor.set_size (-1, -1);
        actor.set_position (-1, -1);
    }

    public Osinfo.Device? get_os_device_by_prop (Osinfo.Os? os, string prop_name, string prop_value) {
        if (os == null)
            return null;

        var devices = os.get_devices_by_property (prop_name, prop_value, true);

        return (devices.get_length () > 0) ? devices.get_nth (0) as Osinfo.Device : null;
    }

    public Gtk.Image get_os_logo (Osinfo.Os? os, int size) {
        var image = new Gtk.Image.from_icon_name ("media-optical", 0);
        image.pixel_size = size;

        if (os != null)
            fetch_os_logo (image, os, size);

        return image;
    }

    public void fetch_os_logo (Gtk.Image image, Osinfo.Os os, int size) {
        var path = get_logo_path (os);

        if (path == null)
            return;

        try {
            var pixbuf = new Gdk.Pixbuf.from_file_at_size (path, size, -1);
            image.set_from_pixbuf (pixbuf);
        } catch (GLib.Error error) {
            warning ("Error loading logo file '%s': %s", path, error.message);
        }
    }

    public int get_enum_value (string value_nick, Type enum_type) {
        var enum_class = (EnumClass) enum_type.class_ref ();
        var val = enum_class.get_value_by_nick (value_nick);
        return_val_if_fail (val != null, -1);

        return val.value;
    }

    public GVir.StorageVol? get_storage_volume (GVir.Connection connection,
                                                GVir.Domain domain,
                                                out GVir.StoragePool pool) {
        pool = connection.find_storage_pool_by_name (Config.PACKAGE_TARNAME);
        if (pool == null)
            // Absence of our pool just means that disk was not created by us.
            return null;

        return pool.get_volume (domain.get_name ());
    }

    public class Pair<T1,T2> {
        public T1 first;
        public T2 second;

        public Pair (T1 first, T2 second) {
            this.first = first;
            this.second = second;
        }
    }

    // FIXME: should be replaced with GUri the day it's available.
    public class Query: GLib.Object {
        string query;
        HashTable<string, string?> params;

        construct {
            params = new HashTable<string, string> (GLib.str_hash, GLib.str_equal);
        }

        public Query (string query) {
            this.query = query;
            parse ();
        }

        public void parse () {
            foreach (var p in query.split ("&")) {
                var pair = p.split ("=");
                if (pair.length != 2)
                    continue;
                params.insert (pair[0], pair[1]);
            }
        }

        public new string? get (string key) {
            return params.lookup (key);
        }
    }

    private string? get_logo_path (Osinfo.Os os, string[] extensions = {".svg", ".png", ".jpg"}) {
        if (extensions.length == 0)
            return null;

        var path = get_pixmap (os.short_id + extensions[0]);
        var file = File.new_for_path (path);
        if (!file.query_exists ()) {
            path = get_pixmap (os.distro + extensions[0]);
            file = File.new_for_path (path);
        }

        if (file.query_exists ())
            return path;
        else
            return get_logo_path (os, extensions[1:extensions.length]);
    }

    [DBus (name = "org.freedesktop.Accounts")]
    interface Fdo.Accounts : Object {
        public abstract async string FindUserByName(string name) throws IOError;
    }

    [DBus (name = "org.freedesktop.Accounts.User")]
    interface Fdo.AccountsUser : Object {
        public abstract bool AutomaticLogin { get; }
        public abstract bool Locked { get; }
        public abstract bool SystemAccount { get; }
        public abstract int32 AccountType { get; }
        public abstract int32 PasswordMode { get; }
        public abstract string Email { owned get; }
        public abstract string HomeDirectory { owned get; }
        public abstract string IconFile { owned get; }
        public abstract string Language { owned get; }
        public abstract string Location { owned get; }
        public abstract string RealName { owned get; }
        public abstract string Shell { owned get; }
        public abstract string UserName { owned get; }
        public abstract string XSession { owned get; }
    }

    public string yes_no (bool value) {
        // FIXME: make it translatable after string freeze
        return value ? "yes" : "no";
    }

    public async bool check_cpu_vt_capability () {
        var result = false;
        var file = File.new_for_path ("/proc/cpuinfo");

        try {
            var stream = new DataInputStream (file.read ());
            string line = null;
            while ((line = yield stream.read_line_async (Priority.DEFAULT)) != null) {
                result = /^flags.*(vmx|svm)/.match (line);
                if (result)
                    break;
            }
        } catch (GLib.Error error) {
            GLib.error (error.message);
        }

        debug ("check_cpu_vt_capability: " + yes_no (result));
        return result;
    }

    public async bool check_module_kvm_loaded () {
        var result = false;
        var file = File.new_for_path ("/proc/modules");

        try {
            var stream = new DataInputStream (file.read ());
            string line = null;
            while ((line = yield stream.read_line_async (Priority.DEFAULT)) != null) {
                result = /^(kvm_intel|kvm_amd)/.match (line);
                if (result)
                    break;
            }
        } catch (GLib.Error error) {
            GLib.error (error.message);
        }

        debug ("check_module_kvm_loaded: " + yes_no (result));
        return result;
    }

    public delegate void RunInThreadFunc () throws  GLib.Error;
    public async void run_in_thread (RunInThreadFunc func) throws GLib.Error {
        GLib.Error e = null;
        GLib.g_io_scheduler_push_job ((job, cancellable) => {
                try {
                    func ();
                } catch (GLib.Error err) {
                    e = err;
                }
                job.send_to_mainloop (() => {
                        run_in_thread.callback ();
                        return false;
                    });
                return false;
            });

        yield;

        if (e != null)
            throw e;
    }

    public async void exec (string[] argv, Cancellable? cancellable) throws GLib.Error {
        SourceFunc continuation = exec.callback;
        GLib.Error error = null;
        var context = MainContext.get_thread_default ();

        g_io_scheduler_push_job ((job) => {
            try {
                exec_sync (argv);
            } catch (GLib.Error err) {
                error = err;
            }

            var source = new IdleSource ();
            source.set_callback (() => {
                continuation ();

                return false;
            });
            source.attach (context);

            return false;
        });

        yield;

        if (error != null)
            throw error;
    }

    public void exec_sync (string[] argv) throws GLib.Error {
        int exit_status = -1;

        Process.spawn_sync (null,
                            argv,
                            null,
                            SpawnFlags.SEARCH_PATH,
                            null,
                            null,
                            null,
                            out exit_status);
        if (exit_status != 0)
            throw new Boxes.Error.COMMAND_FAILED ("Failed to execute: %s", string.joinv (" ", argv));
    }
}
