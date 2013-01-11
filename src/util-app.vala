// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Xml;

namespace Boxes {

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

    public Gdk.RGBA get_color (string desc) {
        Gdk.RGBA color =  Gdk.RGBA ();
        color.parse (desc);
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

    // This can be used to ensure a specific initial allocation for a previously unallocated actor
    public void allocate_actor_no_animation (Clutter.Actor actor,
                                             float x, float y,
                                             float width, float height) {
        var old_duration = actor.get_easing_duration ();
        actor.set_easing_duration (0);
        Clutter.ActorBox box = { x, y, x + width, y + height};
        actor.allocate (box, 0);
        actor.set_easing_duration (old_duration);
    }

    public void fade_actor (Clutter.Actor actor, uint opacity) {
        if (opacity != 0)
            actor.show ();

        // Don't react to use input while fading out
        actor.set_reactive (opacity == 255);

        var transition = actor.get_transition ("animate-opacity");
        if (transition != null)
            actor.remove_transition ("animate-opacity");

        transition = new Clutter.PropertyTransition ("opacity");
        var value = GLib.Value (typeof (uint));
        value.set_uint (opacity);
        transition.set_to_value (value);
        transition.set_duration (App.app.duration);
        transition.set_progress_mode (Clutter.AnimationMode.EASE_OUT_QUAD);
        transition.completed.connect (() => {
            actor.remove_transition ("animate-opacity");
            actor.visible = actor.opacity != 0;
        });
        actor.add_transition ("animate-opacity", transition);
    }

    public Clutter.Transition animate_actor_geometry (float x, float y, float width, float height) {
        var transition = new Clutter.TransitionGroup ();
        transition.set_duration (App.app.duration);
        transition.set_progress_mode (Clutter.AnimationMode.EASE_OUT_QUAD);

        var value = GLib.Value (typeof (float));
        if (x > 0) {
            var x_transition = new Clutter.PropertyTransition ("x");
            value.set_float (x);
            x_transition.set_to_value (value);
            transition.add_transition (x_transition);
        }

        if (y > 0) {
            var y_transition = new Clutter.PropertyTransition ("y");
            value.set_float (y);
            transition.set_to_value (value);
            transition.add_transition (y_transition);
        }

        if (width > 0) {
            var width_transition = new Clutter.PropertyTransition ("width");
            value.set_float (width);
            transition.set_to_value (value);
            transition.add_transition (width_transition);
        }

        if (height > 0) {
            var height_transition = new Clutter.PropertyTransition ("height");
            value.set_float (height);
            transition.set_to_value (value);
            transition.add_transition (height_transition);
        }

        return transition as Clutter.Transition;
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

    public Osinfo.Device? find_device_by_prop (Osinfo.DeviceList devices, string prop_name, string prop_value) {
        var filter = new Osinfo.Filter ();
        filter.add_constraint (prop_name, prop_value);

        var filtered = (devices as Osinfo.List).new_filtered (filter);
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

        var connection = new GVir.Connection ("qemu:///system");

        try {
            connection.open_read_only ();

            var file = File.new_for_path ("/etc/qemu/bridge.conf");
            uint8[] contents;
            file.load_contents (null, out contents, null);

            libvirt_bridge_net_available = (Regex.match_simple ("^allow.*virbr0", (string) contents));
        } catch (GLib.Error error) {
            debug ("%s", error.message);

            libvirt_bridge_net_available = false;
        }

        libvirt_bridge_net_checked = true;

        return libvirt_bridge_net_available;
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

    public async bool check_storage_pool (out string diagnosis) {
        string pool_path;
        diagnosis = "";
        try {
            string standard_output;

            string[] argv = {"virsh", "pool-dumpxml", Config.PACKAGE_TARNAME};

            yield exec (argv, null, out standard_output);
            pool_path = extract_xpath (standard_output, "string(/pool[@type='dir']/target/path)");
        } catch (GLib.Error error) {
            debug (error.message);
            diagnosis = _("Could not get 'gnome-boxes' storage pool information from libvirt. Make sure 'virsh -c qemu:///session pool-dumpxml gnome-boxes' is working.");
            return false;
        }

        if (!FileUtils.test (pool_path, FileTest.EXISTS)) {
            diagnosis = _("%s is known to libvirt as GNOME Boxes's storage pool but this directory does not exist").printf (pool_path);
            return false;
        }
        if (!FileUtils.test (pool_path, FileTest.IS_DIR)) {
            diagnosis = _("%s is known to libvirt as GNOME Boxes's storage pool but is not a directory").printf (pool_path);
            return false;
        }
        if (Posix.access (pool_path, Posix.R_OK | Posix.W_OK | Posix.X_OK) != 0) {
            diagnosis = _("%s is known to libvirt as GNOME Boxes's storage pool but is not user-readable/writable").printf (pool_path);
            return false;
        }

        return true;
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

    public async void copy_file (File src_file, File dest_file, Cancellable? cancellable = null) throws GLib.Error {
        try {
            debug ("Copying '%s' to '%s'..", src_file.get_path (), dest_file.get_path ());
            yield src_file.copy_async (dest_file, 0, Priority.DEFAULT, cancellable);
            debug ("Copied '%s' to '%s'.", src_file.get_path (), dest_file.get_path ());
        } catch (IOError.EXISTS error) {}
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

    public bool is_mime_type (string filename, string mime_type) {
        var file_type = ContentType.guess (filename, null, null);
        var supertype = ContentType.from_mime_type (mime_type);

        return ContentType.is_a (file_type, supertype);
    }

    namespace UUID {
        [CCode (cname = "uuid_generate", cheader_filename = "uuid/uuid.h")]
        internal extern static void generate ([CCode (array_length = false)] uchar[] uuid);
        [CCode (cname = "uuid_unparse", cheader_filename = "uuid/uuid.h")]
        internal extern static void unparse ([CCode (array_length = false)] uchar[] uuid,
                                             [CCode (array_length = false)] uchar[] output);
    }

    string uuid_generate () {
        var udn = new uchar[50];
        var id = new uchar[16];

        UUID.generate (id);
        UUID.unparse (id, udn);

        return (string) udn;
    }

    // shamelessly copied from gnome-documents
    public GLib.Icon create_symbolic_emblem (string name) {
        var pix = Gd.create_symbolic_icon (name, 128);

        if (pix == null)
            pix = new GLib.ThemedIcon (name);

        return pix;
    }
}
