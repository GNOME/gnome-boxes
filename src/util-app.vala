// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Xml;
using Linux;

namespace Boxes {

    public Gtk.CssProvider load_css (string css) {
        var provider = new CssProvider ();
        try {
            var file = File.new_for_uri("resource:///org/gnome/Boxes/" + css);
            provider.load_from_file (file);
        } catch (GLib.Error e) {
            warning ("loading css: %s", e.message);
        }
        return provider;
    }

    public Gdk.Pixbuf load_asset (string asset) throws GLib.Error {
        return new Gdk.Pixbuf.from_resource ("/org/gnome/Boxes/icons/" + asset);
    }

    public Gtk.Builder load_ui (string ui) {
        var builder = new Gtk.Builder ();
        try {
            builder.add_from_resource ("/org/gnome/Boxes/ui/".concat (ui, null));
        } catch (GLib.Error e) {
            error ("Failed to load UI file '%s': %s", ui, e.message);
        }
        return builder;
    }

    public Gdk.RGBA get_color (string desc) {
        Gdk.RGBA color =  Gdk.RGBA ();
        color.parse (desc);
        return color;
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

    public void widget_remove (Gtk.Widget widget) {
        var container = widget.get_parent () as Gtk.Container;

        if (container == null)
            return;

        container.remove (widget);
    }

    public void use_list_box_separator (ListBoxRow row, ListBoxRow? before_row) {
        if (before_row == null) {
            row.set_header (null);

            return;
        }

        var current = row.get_header ();
        if (current == null) {
            current = new Separator (Orientation.HORIZONTAL);
            current.visible = true;

            row.set_header (current);
        }
    }

    public Osinfo.Device? find_device_by_prop (Osinfo.DeviceList devices, string prop_name, string prop_value) {
        var filter = new Osinfo.Filter ();
        filter.add_constraint (prop_name, prop_value);

        var osinfo_list = devices as Osinfo.List;
        var filtered = osinfo_list.new_filtered (filter);
        if (filtered.get_length () > 0)
            return filtered.get_nth (0) as Osinfo.Device;
        else
            return null;
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

    public string serialize_os_title (Osinfo.Media media) {
        var title = "unknown";

        /* Libosinfo lacks some OS variant names, so we do some
           parsing here to compose a unique human-readable media
           identifier. */
        var variant = "";
        var variants = media.get_os_variants ();
        var product = media.os as Osinfo.Product;

        var media_url = "";
        if (media.url != null) {
            media_url = media.url.ascii_down ();
        }

        var variant_id = "";
        if (variants.get_length () > 0) {
            var os_variant = variants.get_nth (0) as Osinfo.OsVariant;
            variant = os_variant.get_name ();

            variant_id = os_variant.get_param_value ("id");
        }

        if (variant == "" && product.name != null) {
            variant = product.name;
            if (variant_id.contains ("server") ||
                (media.url != null && media_url.contains ("server")))
                variant += " Server";
        } else {
            if (media.url != null) {
                var file = File.new_for_uri (media.url);
                title = file.get_basename ().replace ("_", "");
            }
        }

        var subvariant = "";
        if (variant_id.contains ("netinst"))
            subvariant = "(netinst)";
        else if (variant_id.contains ("minimal"))
            subvariant = "(minimal)";

        if (subvariant == "" && media.url != null) {
            if (media.url.contains ("netinst"))
                subvariant = "(netinst)";
            else if (media_url.contains ("minimal"))
                subvariant = "(minimal)";
            else if (media_url.contains ("dvd"))
                subvariant = "(DVD)";
        }

        var is_live = media.live ? " (" + _("Live") + ")" : "";

        title = @"$variant $(media.architecture) $subvariant $is_live";

        /* Strip consequent whitespaces */
        return title.replace ("  ", "");
    }

    public async GLib.List<Osinfo.Media>? get_recommended_downloads () {
        return yield parse_recommended_downloads_file (
            "resource:///org/gnome/Boxes/recommended-downloads.xml");
    }

    public async GLib.List<Osinfo.Media>? fetch_recommended_downloads_from_net () {
        var settings = App.app.main_window.settings;
        var url = settings.get_string ("recommended-downloads-url");
        if (url == null || url == "")
            return null;

        var remote_file = GLib.File.new_for_uri (url);
        string cached_path = get_logo_cache ("recommended-downloads.xml");
        GLib.File cached_file = GLib.File.new_for_path (cached_path);

        var download = new Download (remote_file, cached_file, new ActivityProgress ()); 
        try {
            yield Downloader.get_default ().download_from_http (download);
        } catch (GLib.Error error) {
            message ("Failed to download recommended-downloads file: %s", error.message);

            if (!cached_file.query_exists ())
                return null;
        }

        return yield parse_recommended_downloads_file (cached_file.get_uri ());
    }

    private async GLib.List<Osinfo.Media>? parse_recommended_downloads_file (string uri) {
        uint8[] contents;

        try {
            File file = File.new_for_uri (uri);

            file.load_contents (null, out contents, null);
        } catch (GLib.Error e) {
            warning ("Failed to load recommended downloads file: %s", e.message);

            return null;
        }

        Xml.Doc* doc = Xml.Parser.parse_doc ((string)contents);
        if (doc == null)
            return null;

        Xml.Node* root = doc->get_root_element ();
        if (root == null || root->name != "list") {
            warning ("Failed to parse recommended downloads");

            return null;
        }

        GLib.List<Osinfo.Media> list = new GLib.List<Osinfo.Media> ();
        var os_db = MediaManager.get_default ().os_db;
        for (Xml.Node* iter = root->children; iter != null; iter = iter->next) {
            var os_id = iter->get_prop ("id");
            if (os_id == null)
                continue;

            Osinfo.Os? os;
            try {
                os = yield os_db.get_os_by_id (os_id);
            } catch (OSDatabaseError error) {
                // If the OS wasn't found, it means an os_id prefix was given
                os = yield os_db.get_latest_release_for_os_prefix (os_id);
            }

            if (os == null) {
                warning ("Failed to load %s", os_id);

                continue;
            }

            var media_list = os.get_media_list ();
            if (media_list == null || media_list.get_length () == 0)
                continue;

            var media = media_list.get_nth (0) as Osinfo.Media;
            if (media.url != null || os_id.has_prefix ("http://redhat.com"))
                list.append (media);

            for (Xml.Node* child_iter = iter->children; child_iter != null; child_iter = child_iter->next) {
                if (child_iter->type != Xml.ElementType.ELEMENT_NODE)
                    continue;

                string content = child_iter->get_content ();
                string node_name = child_iter->name;
                if (node_name == "url")
                    media.url = content;
                else
                    media.set_data (node_name, content);
            }
        }

        return list;
    }

    public async GVir.StoragePool ensure_storage_pool (GVir.Connection connection) throws GLib.Error {
        var pool = get_storage_pool (connection);
        if (pool == null) {
            debug ("Creating storage pool..");
            var config = VMConfigurator.get_pool_config ();
            pool = connection.create_storage_pool (config, 0);
            yield pool.build_async (0, null);
            debug ("Created storage pool.");
        }

        // Ensure pool directory exists in case user deleted it after pool creation
        var pool_path = get_user_pkgdata ("images");
        ensure_directory (pool_path);

        if (pool.get_info ().state == GVir.StoragePoolState.INACTIVE)
            yield pool.start_async (0, null);
        yield pool.refresh_async (null);
        pool.set_autostart (true);

        return pool;
    }

    public GVir.StoragePool? get_storage_pool (GVir.Connection connection) {
        return connection.find_storage_pool_by_name (Config.PACKAGE_TARNAME);
    }

    public GVir.StorageVol? get_storage_volume (GVir.Connection connection, GVir.Domain domain) {
        var pool = get_storage_pool (connection);
        if (pool == null)
            // Absence of our pool just means that disk was not created by us.
            return null;

        return pool.get_volume (domain.get_name ());
    }

    private static bool libvirt_bridge_net_checked = false;
    private static bool libvirt_bridge_net_available = false;

    public bool is_libvirt_bridge_net_available () {
        if (libvirt_bridge_net_checked)
            return libvirt_bridge_net_available;

        try {
            // First check if bridge interface is up
            var sock = Posix.socket (Posix.AF_INET, Posix.SOCK_STREAM, 0);
            if (sock < 0)
                throw (GLib.IOError) new GLib.Error (G_IO_ERROR,
                                                     g_io_error_from_errno (Posix.errno),
                                                     "Failed to create a socket");

            var req = Network.IfReq ();
            var if_name = "virbr0";
            for (var i = 0; i <= if_name.length;  i++)
                req.ifr_name[i] = (char) if_name[i];

            if (Posix.ioctl (sock, Network.SIOCGIFFLAGS, ref req) < 0 ||
                !(Network.IfFlag.UP in req.ifr_flags)) {
                debug ("Interface '%s' is either not available or not up.", if_name);

                return false;
            }

            // Now check if unprivileged qemu is allowed to access it
            var file = File.new_for_path ("/etc/qemu/bridge.conf");
            uint8[] contents;
            try {
                file.load_contents (null, out contents, null);
            } catch (IOError.NOT_FOUND error) {
                file = File.new_for_path ("/etc/qemu-kvm/bridge.conf");
                file.load_contents (null, out contents, null);
            }

            libvirt_bridge_net_available = (Regex.match_simple ("(?m)^allow.*virbr0", (string) contents));
        } catch (GLib.Error error) {
            debug ("%s", error.message);

            libvirt_bridge_net_available = false;
        }

        libvirt_bridge_net_checked = true;

        return libvirt_bridge_net_available;
    }

    private static GVir.Connection? system_virt_connection = null;

    public async GVir.Connection get_system_virt_connection () throws GLib.Error {
        if (system_virt_connection != null)
            return system_virt_connection;

        system_virt_connection = new GVir.Connection ("qemu+unix:///system");

        yield system_virt_connection.open_read_only_async (null);

        debug ("Connected to system libvirt, now fetching domains..");
        yield system_virt_connection.fetch_domains_async (null);
        yield system_virt_connection.fetch_networks_async (null);

        return system_virt_connection;
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
            int index = standard_output.index_of ("<capabilities");

            if (index < 0)
                throw new Boxes.Error.INVALID ("Unexpected output while running command '%s %s'", argv[0], argv[1]);

            standard_output = standard_output.substring (index);
            var kvm = extract_xpath (standard_output,
                                     "string(/capabilities/guest[os_type='hvm']/arch/domain[@type='kvm']/../emulator)");
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
            warning ("Failed to read file /proc/cpuinfo: %s", error.message);
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
            warning ("Failed to read file /proc/modules: %s", error.message);
        }

        debug ("check_module_kvm_loaded: " + yes_no (result));
        return result;
    }

    public async bool check_storage_pool (out string diagnosis) {
        string pool_path;
        diagnosis = "";
        try {
            string standard_output;

            string[] argv = {"virsh", "pool-dumpxml", Config.PACKAGE_TARNAME};

            yield exec (argv, null, out standard_output);
            int index = standard_output.index_of ("<pool");

            if (index < 0)
                throw new Boxes.Error.INVALID ("Unexpected output while running command '%s %s %s'", argv[0], argv[1], argv[2]);

            standard_output = standard_output.substring (index);
            pool_path = extract_xpath (standard_output, "string(/pool[@type='dir']/target/path)");
        } catch (GLib.Error error) {
            debug (error.message);
            diagnosis = _("Could not get “gnome-boxes” storage pool information from libvirt. Make sure “virsh -c qemu:///session pool-dumpxml gnome-boxes” is working.");
            return false;
        }

        if (!FileUtils.test (pool_path, FileTest.EXISTS)) {
            diagnosis = _("%s is known to libvirt as GNOME Boxes’s storage pool but this directory does not exist").printf (pool_path);
            return false;
        }
        if (!FileUtils.test (pool_path, FileTest.IS_DIR)) {
            diagnosis = _("%s is known to libvirt as GNOME Boxes’s storage pool but is not a directory").printf (pool_path);
            return false;
        }
        if (Posix.access (pool_path, Posix.R_OK | Posix.W_OK | Posix.X_OK) != 0) {
            diagnosis = _("%s is known to libvirt as GNOME Boxes’s storage pool but is not user-readable/writable").printf (pool_path);
            return false;
        }

        return true;
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

    // Warning: architecture compability is not computative. e.g "i386" is compatible with "i686" but "i686" is
    // incompatible with "i386".
    public enum CPUArchCompatibility {
        INCOMPATIBLE             = -1, // First architecture is incompatible to second one
        IDENTICAL                = 0,  // First architecture is identical to second one
        COMPATIBLE               = 1,  // First architecture is compatible with second one
        COMPATIBLE_DIFF_WORDSIZE = 2,  // First architecture is more modern than but compatible
                                      // with second one but has different word-size
    }

    public CPUArchCompatibility compare_cpu_architectures (string arch1, string arch2) {
        switch (arch2) {
        case "i386":
            switch (arch1) {
            case "i386":
                return CPUArchCompatibility.IDENTICAL;
            case "i486":
            case "i586":
            case "i686":
                return CPUArchCompatibility.COMPATIBLE;
            case "x86_64":
                return CPUArchCompatibility.COMPATIBLE_DIFF_WORDSIZE;
            default:
                return CPUArchCompatibility.INCOMPATIBLE;
            }
        case "i486":
            switch (arch1) {
            case "i486":
                return CPUArchCompatibility.IDENTICAL;
            case "i586":
            case "i686":
                return CPUArchCompatibility.COMPATIBLE;
            case "x86_64":
                return CPUArchCompatibility.COMPATIBLE_DIFF_WORDSIZE;
            default:
                return CPUArchCompatibility.INCOMPATIBLE;
            }
        case "i586":
            switch (arch1) {
            case "i586":
                return CPUArchCompatibility.IDENTICAL;
            case "i686":
                return CPUArchCompatibility.COMPATIBLE;
            case "x86_64":
                return CPUArchCompatibility.COMPATIBLE_DIFF_WORDSIZE;
            default:
                return CPUArchCompatibility.INCOMPATIBLE;
            }
        case "i686":
            switch (arch1) {
            case "i686":
                return CPUArchCompatibility.IDENTICAL;
            case "x86_64":
                return CPUArchCompatibility.COMPATIBLE_DIFF_WORDSIZE;
            default:
                return CPUArchCompatibility.INCOMPATIBLE;
            }
        case "x86_64":
            switch (arch1) {
            case "x86_64":
                return CPUArchCompatibility.IDENTICAL;
            default:
                return CPUArchCompatibility.INCOMPATIBLE;
            }
        case Osinfo.ARCHITECTURE_ALL:
            return CPUArchCompatibility.COMPATIBLE;
        default:
            switch (arch1) {
            case Osinfo.ARCHITECTURE_ALL:
                return CPUArchCompatibility.IDENTICAL;
            default:
                return CPUArchCompatibility.INCOMPATIBLE;
            }
        }
    }

    [DBus (name = "org.freedesktop.timedate1")]
    public interface Fdo.timedate1 : Object {
        public abstract string timezone { owned get; set; }
    }

    public string? get_timezone () {
        try {
            return get_timezone_from_systemd ();
        } catch (GLib.Error e) {
            // A system without systemd. :( Lets try the hack'ish way.
            debug ("Failed to get timezone from systemd: %s", e.message);
            try {
                return get_timezone_from_linux ();
            } catch (GLib.Error e) {
                warning ("Failed to find system timezone: %s", e.message);

                return null;
            }
        }
    }

    public string get_timezone_from_systemd () throws GLib.Error {
        Fdo.timedate1 timedate = Bus.get_proxy_sync (BusType.SYSTEM,
                                                     "org.freedesktop.timedate1",
                                                     "/org/freedesktop/timedate1");
        if (timedate.timezone == null)
            throw new Boxes.Error.INVALID ("Failed to get timezone from systemd");

        return timedate.timezone;
    }

    private const string TZ_FILE = "/etc/localtime";

    public string get_timezone_from_linux () throws GLib.Error {
        var file = File.new_for_path (TZ_FILE);
        if (!file.query_exists ())
            throw new Boxes.Error.INVALID ("Timezone file not found in expected location '%s'", TZ_FILE);

        var info = file.query_info (FileAttribute.STANDARD_SYMLINK_TARGET, FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
        var target = info.get_symlink_target ();
        if (target == null)
            throw new Boxes.Error.INVALID ("Timezone file '%s' is expected to be a symlink", TZ_FILE);

        var tokens = target.split ("zoneinfo/");
        if (tokens == null || tokens.length < 2)
            throw new Boxes.Error.INVALID ("Timezone file in unexpected location '%s'", target);

        return tokens[1];
    }

    // Move all configurations from ~/.cache to ~/.config
    public async void move_configs_from_cache () {
        yield move_config_from_cache ("unattended");
        yield move_config_from_cache ("sources");
    }

    private async void move_config_from_cache (string config_name) {
        var path = get_cache (config_name);
        var cache_dir = File.new_for_path (path);
        var config_path = Path.build_filename (get_user_pkgconfig (), config_name);

        try {
            var enumerator = yield cache_dir.enumerate_children_async (FileAttribute.STANDARD_NAME, 0);
            while (true) {
                var files = yield enumerator.next_files_async (10);
                if (files == null)
                    break;

                foreach (var info in files) {
                    path = Path.build_filename (cache_dir.get_path (), info.get_name ());
                    var cache_file = File.new_for_path (path);
                    path = Path.build_filename (config_path, info.get_name ());
                    var config_file = File.new_for_path (path);

                    cache_file.move (config_file, FileCopyFlags.OVERWRITE);
                    debug ("moved %s to %s", cache_file.get_path (), config_file.get_path ());
                }
            }

            yield cache_dir.delete_async ();
        } catch (IOError.NOT_FOUND error) {
            // That just means config doesn't exist in cache dir
        } catch (GLib.Error error) {
            warning (error.message);
        }
    }

    public Gdk.Pixbuf? paint_empty_frame (int width, int height) {
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);

        return Gdk.pixbuf_get_from_surface (surface, 0, 0, width, height);
    }

    public Gdk.Pixbuf? round_image (Gdk.Pixbuf source) {
        int size = source.width;
        Cairo.Surface surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, size, size);
        Cairo.Context cr = new Cairo.Context (surface);

        cr.arc (size / 2, size / 2, size / 2, 0, 2 * GLib.Math.PI);
        cr.clip ();
        cr.new_path ();

        Gdk.cairo_set_source_pixbuf (cr, source, 0, 0);
        cr.paint ();

        return Gdk.pixbuf_get_from_surface (surface, 0, 0, size, size);
    }

    private DBusProxy? create_gnome_settings_dbus_proxy () {
        DBusProxy? proxy = null;
        try {
            proxy = new DBusProxy.for_bus_sync (BusType.SESSION,
                                                DBusProxyFlags.NONE,
                                                null,
                                                "org.gnome.Settings",
                                                "/org/gnome/Settings",
                                                "org.gtk.Actions");
        } catch (GLib.Error error) {
            debug ("Failed to launch org.gnome.Settings. Fallback to org.gnome.ControlCenter");
        }

        try {
            proxy = new DBusProxy.for_bus_sync (BusType.SESSION,
                                                DBusProxyFlags.NONE,
                                                null,
                                                "org.gnome.ControlCenter",
                                                "/org/gnome/ControlCenter",
                                                "org.gtk.Actions");
        } catch (GLib.Error error) {
            debug ("Failed to launch org.gnome.ControlCenter");
        }

        return proxy;
    }

    public void open_permission_settings () {
        try {
            var proxy = create_gnome_settings_dbus_proxy ();
            if (proxy == null)
                throw new GLib.IOError.FAILED ("Couldn't create DBusProxy for GNOME Settings");

            var builder = new VariantBuilder (new VariantType ("av"));
            builder.add ("v", new Variant.string (Config.APPLICATION_ID));
            var param = new Variant.tuple ({
                new Variant.string ("launch-panel"),
                new Variant.array (new VariantType ("v"), {
                    new Variant ("v", new Variant ("(sav)", "applications", builder)),
                }),
                new Variant.array (new VariantType ("{sv}"), {})
            });

            proxy.call_sync ("Activate", param, DBusCallFlags.NONE, -1);
        } catch (GLib.Error error) {
            warning ("Failed to launch gnome-control-center: %s", error.message);
        }
    }
}
