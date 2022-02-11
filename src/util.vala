// This file is part of GNOME Boxes. License: LGPLv2+
using Archive;
using Config;

public errordomain Boxes.Error {
    INVALID,
    RESTORE_FAILED,
    START_FAILED,
    COMMAND_FAILED
}

namespace Boxes {

    public string get_pkgdata (string? file_name = null) {
        return Path.build_filename (DATADIR, Config.PACKAGE_TARNAME, file_name);
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

    public string get_custom_osinfo_db () {
        return get_pkgdata ("osinfo");
    }

    public string get_user_agent () {
        var user_agent = Config.DISTRIBUTOR_NAME + "/" + Config.DISTRIBUTOR_VERSION + " " +
                         Config.PACKAGE_TARNAME + "/" + Config.PACKAGE_VERSION;

        return user_agent;
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

    public string? get_system_pkgcache (string? file_name = null) {
        var dir = Path.build_filename (CACHEDIR, Config.PACKAGE_TARNAME);
        if (!FileUtils.test (dir, FileTest.EXISTS))
            return null;

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

    public string get_utf8_basename (string path) {
        var file = File.new_for_path (path);
        string name = file.get_parse_name ();
        try {
            var info = file.query_info (FileAttribute.STANDARD_DISPLAY_NAME, 0);
            name = info.get_display_name ();
        } catch (GLib.Error e) {
        }
        return name;
    }

    public string? get_system_logo_cache (string? file_name = null) {
        var system_pkgcache = get_system_pkgcache ();
        if (system_pkgcache == null)
            return null;

        var dir = Path.build_filename (system_pkgcache, "logos");
        if (!FileUtils.test (dir, FileTest.EXISTS))
            return null;

        return Path.build_filename (dir, file_name);
    }

    public string get_logo_cache (string? file_name = null) {
        return get_cache ("logos", file_name);
    }

    public string get_drivers_cache (string? file_name = null) {
        return get_cache ("drivers", file_name);
    }

    public string get_cache (string cache_name, string? file_name = null) {
        var dir = get_user_pkgcache (cache_name);

        ensure_directory (dir);

        return Path.build_filename (dir, file_name);
    }

    public string? get_system_drivers_cache (string? file_name = null) {
        var system_pkgcache = get_system_pkgcache ();
        if (system_pkgcache == null)
            return null;

        var dir = Path.build_filename (get_system_pkgcache (), "drivers");
        if (!FileUtils.test (dir, FileTest.EXISTS))
            return null;

        return Path.build_filename (dir, file_name);
    }

    public string get_screenshot_filename (string prefix) {
        return get_user_pkgcache (prefix + "-screenshot.png");
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

    public bool keyfile_save (KeyFile key_file, string file_name, bool overwrite = false) {
        try {
            if (!overwrite && FileUtils.test (file_name, FileTest.EXISTS))
                return false;

            return FileUtils.set_contents(file_name, key_file.to_data (null));
        } catch (GLib.Error error) {
            warning (error.message);
            return false;
        }
    }

    public async void output_stream_write (OutputStream stream, uint8[] buffer) throws GLib.IOError {
        var length = buffer.length;
        ssize_t i = 0;

        while (i < length)
            i += yield stream.write_async (buffer[i:length]);
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

    public async void exec (string[] argv,
                            Cancellable? cancellable,
                            out string? standard_output = null,
                            out string? standard_error = null) throws GLib.Error {
        string std_output = "";
        string std_error = "";
        // make sure vala makes a copy of argv that will be kept alive until run_in_thread finishes
        string[] argv_copy = argv;

        yield AsyncLauncher.get_default ().launch (() => {
           exec_sync (argv_copy, out std_output, out std_error);
        });

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

    public int get_enum_value (string value_nick, Type enum_type) {
        var enum_class = (EnumClass) enum_type.class_ref ();
        var val = enum_class.get_value_by_nick (value_nick);
        return_val_if_fail (val != null, -1);

        return val.value;
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

    public class ActivityProgress : GLib.Object {
        public double progress { get; set; }
        public string info { get; set; default = ""; }

        public ActivityProgress add_child_activity (double scale) {
            var child_progress = new ActivityProgress ();
            var last_child_progress = 0d;
            child_progress.notify["progress"].connect (() => {
                var child_progress_delta = child_progress.progress - last_child_progress;
                this.progress += child_progress_delta * scale;
                last_child_progress = child_progress.progress;
            });

            return child_progress;
        }
    }

    public bool is_set (string? str) {
        return str != null && str != "";
    }

    public string yes_no (bool value) {
        return value ? _("yes") : _("no");
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

    public delegate Archive.Result LibarchiveFunction ();

    public static void execute_libarchive_function (Archive.Archive    archive,
                                                    LibarchiveFunction function,
                                                    uint               num_retries = 1)
                                                    throws GLib.IOError {
        switch (function ()) {
        case Archive.Result.OK:
            return;

        case Archive.Result.EOF:
            throw new GLib.IOError.CLOSED ("End of file reached.");

        case Archive.Result.RETRY:
            if (num_retries < 1)
                break;

            execute_libarchive_function (archive, function, num_retries - 1);
            return;

        case Archive.Result.WARN:
            warning ("%s", archive.error_string ());
            return;

        default:
            break;
        }

        var msg = archive.error_string ();
        if (msg == "Unrecognized archive format")
            throw new GLib.IOError.NOT_SUPPORTED ("%s", msg);

        throw new GLib.IOError.FAILED ("%s", msg);
    }

    public static bool get_next_header (Archive.Read              archive,
                                        out unowned Archive.Entry iterator,
                                        uint                      num_retries = 1)
                                        throws GLib.IOError {
        // Create own iterator that can be captured by a lambda
        unowned Archive.Entry local_iterator = null;
        try {
            execute_libarchive_function (archive, () => {
                return archive.next_header (out local_iterator);
            }, num_retries);

            iterator = local_iterator;
            return true;
        } catch (GLib.IOError.CLOSED e) {
            iterator = local_iterator;
            return false;
        }
    }

    // shamelessly copied form gnome-contacts
    private static unichar strip_char (unichar ch) {
        switch (ch.type ()) {
        case UnicodeType.CONTROL:
        case UnicodeType.FORMAT:
        case UnicodeType.UNASSIGNED:
        case UnicodeType.NON_SPACING_MARK:
        case UnicodeType.COMBINING_MARK:
        case UnicodeType.ENCLOSING_MARK:
            /* Ignore those */
            return 0;
        default:
            return ch.tolower ();
        }
    }

    // shamelessly copied form gnome-contacts
    public static string canonicalize_for_search (string str) {
        unowned string s;
        var buf = new unichar[18];
        var res = new StringBuilder ();
        for (s = str; s[0] != 0; s = s.next_char ()) {
            var c = strip_char (s.get_char ());
            if (c != 0) {
                var size = c.fully_decompose (false, buf);
                if (size > 0)
                    res.append_unichar (buf[0]);
            }
        }
        return res.str;
    }
}
