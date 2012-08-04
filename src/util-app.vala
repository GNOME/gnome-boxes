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

    public GVir.StorageVol? get_storage_volume (GVir.Connection connection,
                                                GVir.Domain domain,
                                                out GVir.StoragePool pool) {
        pool = connection.find_storage_pool_by_name (Config.PACKAGE_TARNAME);
        if (pool == null)
            // Absence of our pool just means that disk was not created by us.
            return null;

        return pool.get_volume (domain.get_name ());
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
}
