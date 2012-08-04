// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Config;
using Xml;

public errordomain Boxes.Error {
    INVALID,
    COMMAND_FAILED
}

namespace Boxes {

    public string get_pkgdata (string? file_name = null) {
        return Path.build_filename (DATADIR, Config.PACKAGE_TARNAME, file_name);
    }

    public string get_style (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "style", file_name);
    }

    public string get_pixmap (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "pixmaps", file_name);
    }

    public string get_unattended (string? file_name = null) {
        var dir = Path.build_filename (get_pkgdata (), "unattended");

        return Path.build_filename (dir, file_name);
    }

    public string get_pkgdata_source (string? file_name = null) {
        return Path.build_filename (get_pkgdata (), "sources", file_name);
    }

    public string get_user_unattended (string? file_name = null) {
        var dir = Path.build_filename (get_user_pkgconfig (), "unattended");

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public string get_user_pkgcache (string? file_name = null) {
        var dir = Path.build_filename (Environment.get_user_cache_dir (), Config.PACKAGE_TARNAME);

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public string get_user_pkgconfig (string? file_name = null) {
        var dir = Path.build_filename (Environment.get_user_config_dir (), Config.PACKAGE_TARNAME);

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public string get_user_pkgdata (string? file_name = null) {
        var dir = Path.build_filename (Environment.get_user_data_dir (), Config.PACKAGE_TARNAME);

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public bool has_user_pkgconfig_sources () {
        return FileUtils.test (Path.build_filename (get_user_pkgconfig (), "sources"), FileTest.IS_DIR);
    }

    public string get_user_pkgconfig_source (string? file_name = null) {
        var dir = Path.build_filename (get_user_pkgconfig (), "sources");

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public void ensure_directory (string dir) {
        try {
            var file = GLib.File.new_for_path (dir);
            file.make_directory_with_parents (null);
        } catch (IOError.EXISTS error) {
        } catch (GLib.Error error) {
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
            id = icon_view.button_release_event.connect ((w, event) => {
                Gtk.TreePath? path;

                if (event.button == 1) {
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

    public void fade_actor (Clutter.Actor actor, uint opacity) {
        if (opacity != 0)
            actor.show ();
        // Don't react to use input while fading out
        actor.set_reactive (opacity == 255);
        actor.save_easing_state ();
        actor.set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUAD);
        actor.set_easing_duration (App.app.duration);
        actor.opacity = opacity;
        var t = actor.get_transition ("opacity");
        t.completed.connect ( () => {
            actor.visible = actor.opacity != 0;
        });
        actor.restore_easing_state ();
    }

    public delegate void ActorFunc (Clutter.Actor actor);

    public void actor_add (Clutter.Actor actor, Clutter.Actor container) {
        if (actor.get_parent () == container)
            return;

        actor_remove (actor);
        container.add_child (actor);
    }

    public void actor_remove (Clutter.Actor actor) {
        var container = actor.get_parent ();

        if (container == null)
            return;

        container.remove_child (actor);
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
        return value ? N_("yes") : N_("no");
    }

    public string indent (string space, string text) {
        var indented = "";

        foreach (var l in text.split ("\n")) {
            if (indented.length != 0)
                indented += "\n";

            if (l.length != 0)
                indented += space + l;
        }

        return indented;
    }

    public async bool check_selinux_context_default (out string diagnosis) {
        diagnosis = "";

        try {
            string standard_output;

            string[] argv = {"restorecon",
                             "-nrv",
                             get_user_pkgconfig (),
                             get_user_pkgdata (),
                             get_user_pkgcache ()};

            yield exec (argv, null, out standard_output);

            if (standard_output.length == 0)
                return true;

            argv[1] = "-r";

            diagnosis = _("Your SELinux context looks incorrect, you can try to fix it by running:\n%s").printf (string.joinv (" ", argv));
            return false;

        } catch (GLib.SpawnError.NOEXEC error) {
            diagnosis = _("SELinux not installed?");
            return true;

        } catch (GLib.Error error) {
            warning (error.message);
        }

        return false;
    }

    public async bool check_libvirt_kvm () {
        try {
            string standard_output;

            string[] argv = {"virsh", "capabilities"};

            yield exec (argv, null, out standard_output);
            var kvm = extract_xpath (standard_output, "string(/capabilities/guest[os_type='hvm']/arch/domain[@type='kvm']/emulator)");
            return kvm.length != 0;

        } catch (GLib.SpawnError.NOEXEC error) {
            critical ("libvirt is not installed correctly");
        } catch (GLib.Error error) {
            warning (error.message);
        }

        return false;
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
    public async void run_in_thread (RunInThreadFunc func, Cancellable? cancellable = null) throws GLib.Error {
        GLib.Error e = null;
        GLib.IOSchedulerJob.push ((job, cancellable) => {
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
        }, GLib.Priority.DEFAULT, cancellable);

        yield;

        if (e != null)
            throw e;
    }

    public async void exec (string[] argv,
                            Cancellable? cancellable,
                            out string? standard_output = null,
                            out string? standard_error = null) throws GLib.Error {

        // FIXME: https://bugzilla.gnome.org/show_bug.cgi?id=681136
        string std_output = "";
        string std_error = "";

        yield run_in_thread (() => {
           exec_sync (argv, out std_output, out std_error);
        }, cancellable);

        standard_output = std_output;
        standard_error = std_error;
    }

    public void exec_sync (string[] argv,
                           out string? standard_output = null,
                           out string? standard_error = null) throws GLib.Error {
        int exit_status = -1;

        Process.spawn_sync (null,
                            argv,
                            null,
                            SpawnFlags.SEARCH_PATH,
                            null,
                            out standard_output,
                            out standard_error,
                            out exit_status);

        if (exit_status != 0)
            throw new Boxes.Error.COMMAND_FAILED ("Failed to execute: %s", string.joinv (" ", argv));
    }

    // FIXME: Better ways to remove alpha more than welcome
    private Gdk.Pixbuf remove_alpha (Gdk.Pixbuf pixbuf) {
        const uint8 ALPHA_TRESHOLD = 50;

        return_val_if_fail (pixbuf.get_n_channels () == 4 && pixbuf.get_bits_per_sample () == 8, pixbuf);

        var width = pixbuf.get_width ();
        var height = pixbuf.get_height ();
        var rowstride = pixbuf.get_rowstride ();
        unowned uint8[] orig_pixels = pixbuf.get_pixels ();
        var pixels = new uint8[rowstride * height];

        for (var i = 0; i < height; i++) {
            for (var j = 0, k = 0; j < width * 4; j += 4, k += 3) {
                var orig_index = rowstride * i + j;
                var index = rowstride * i + k;

                if (orig_pixels[orig_index + 3] < ALPHA_TRESHOLD) {
                    pixels[index] = 0xFF;
                    pixels[index + 1] = 0xFF;
                    pixels[index + 2] = 0xFF;
                } else {
                    pixels[index] = orig_pixels[orig_index];
                    pixels[index + 1] = orig_pixels[orig_index + 1];
                    pixels[index + 2] = orig_pixels[orig_index + 2];
                }
            }
        }

        return new Gdk.Pixbuf.from_data (pixels,
                                         pixbuf.get_colorspace (),
                                         false,
                                         8,
                                         width,
                                         height,
                                         rowstride,
                                         null);
    }

    public void draw_as_css_box (Widget widget) {
        widget.draw.connect ((cr) => {
            var context = widget.get_style_context ();
            Gtk.Allocation allocation;
            widget.get_allocation (out allocation);
            context.render_background (cr,
                                       0, 0,
                                       allocation.width, allocation.height);
            context.render_frame (cr,
                                  0, 0,
                                  allocation.width, allocation.height);
            return false;
         });
    }

    public void delete_file (File file) throws GLib.Error {
        try {
            debug ("Removing '%s'..", file.get_path ());
            file.delete ();
            debug ("Removed '%s'.", file.get_path ());
        } catch (IOError.NOT_FOUND e) {
            debug ("File '%s' was already deleted", file.get_path ());
        }
    }

    public delegate bool ForeachFilenameFromDirFunc (string filename) throws GLib.Error;

    public async void foreach_filename_from_dir (File dir, ForeachFilenameFromDirFunc func) {
        try {
            var enumerator = yield dir.enumerate_children_async (FileAttribute.STANDARD_NAME, 0);
            while (true) {
                var files = yield enumerator.next_files_async (10);
                if (files == null)
                    break;

                foreach (var file in files) {
                    if (func (file.get_name ()))
                        break;
                }
            }
        } catch (GLib.Error error) {
            warning (error.message);
        }
    }
}
