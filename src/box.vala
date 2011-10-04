/*
 * Copyright (C) 2011 Red Hat, Inc.
 *
 * Authors: Marc-André Lureau <marcandre.lureau@gmail.com>
 *          Zeeshan Ali (Khattak) <zeeshanak@gnome.org>
 *
 * This file is part of GNOME Boxes.
 *
 * GNOME Boxes is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * GNOME Boxes is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

using GLib;
using Clutter;
using Gdk;
using Gtk;
using GVir;

public abstract class Boxes.Display: GLib.Object {
    protected HashTable<int, Gtk.Widget?> displays;

    public signal void show (int display_id);
    public signal void hide (int display_id);
    public signal void disconnected ();

    public abstract Gtk.Widget get_display (int n) throws Boxes.Error;
    public abstract void connect_it ();
    public abstract void disconnect_it ();

    public override void constructed () {
        this.displays = new HashTable<int, Gtk.Widget> (direct_hash, direct_equal);
    }

    ~Boxes() {
        disconnect_it ();
    }
}

public class Boxes.Box: Boxes.CollectionItem {
    public Boxes.App app;
    public BoxActor actor;
    public DomainState state {
        get {
            try {
                return this.domain.get_info ().state;
            } catch (GLib.Error error) {
                return DomainState.NONE;
            }
        }
    }

    private GVir.Domain _domain;
    public GVir.Domain domain {
        get { return this._domain; }
        construct set {
            this._domain = value;
        }
    }

    private Display display;

    public Box (Boxes.App app, GVir.Domain domain) {
        Object (domain: domain);
        this.app = app;

        this.name = domain.get_name ();
        this.actor = new BoxActor (this);

        this.update_screenshot.begin ();
        Timeout.add_seconds (5, () => {
            this.update_screenshot.begin ();

            return true;
        });

        app.state.completed.connect ( () => {
            if (app.state.state == "display") {
                if (app.selected_box != this)
                    return;

                try {
                    this.actor.show_display (this.display.get_display (0));
                } catch (Boxes.Error error) {
                        warning (error.message);
                }
            }
        });
    }

    public Clutter.Actor get_clutter_actor () {
        return this.actor.actor;
    }

    public async bool take_screenshot () throws GLib.Error {
        if (this.state != DomainState.RUNNING &&
            this.state != DomainState.PAUSED)
            return false;

        var stream = this.app.connection.get_stream (0);
        var file_name = this.get_screenshot_filename ();
        var file = File.new_for_path (file_name);
        var output_stream = yield file.replace_async (null, false, FileCreateFlags.REPLACE_DESTINATION);
        var input_stream = stream.get_input_stream ();
        this.domain.screenshot (stream, 0, 0);

        var buffer = new uint8[65535];
        ssize_t length = 0;
        do {
            length = yield input_stream.read_async (buffer);
            yield output_stream_write (output_stream, buffer[0:length]);
        } while (length > 0);

        return true;
    }

    public bool connect_display () {
        this.update_display ();

        if (this.display == null)
            return false;

        this.display.connect_it ();

        return true;
    }

    private string get_screenshot_filename (string ext = "ppm") {
        var uuid = this.domain.get_uuid ();

        return get_pkgcache (uuid + "-screenshot." + ext);
    }

    private async void update_screenshot () {
        Gdk.Pixbuf? pixbuf = null;

        try {
            yield this.take_screenshot ();
            pixbuf = new Gdk.Pixbuf.from_file (this.get_screenshot_filename ());
        } catch (GLib.Error error) {
            if (!(error is FileError.NOENT))
                warning (error.message);
        }

        if (pixbuf == null)
            pixbuf = draw_fallback_vm (128, 96);

        try {
            this.actor.set_screenshot (pixbuf);
        } catch (GLib.Error err) {
            warning (err.message);
        }
    }

    private static Gdk.Pixbuf draw_fallback_vm (int width, int height) {
        Gdk.Pixbuf pixbuf = null;

        try {
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
            var context = new Cairo.Context (surface);

            var pattern = new Cairo.Pattern.linear (0, 0, 0, height);
            pattern.add_color_stop_rgb (0, 0.260, 0.260, 0.260);
            pattern.add_color_stop_rgb (1, 0.220, 0.220, 0.220);

            context.set_source (pattern);
            context.paint ();

            int size = (int) (height * 0.5);
            var icon_info = IconTheme.get_default ().lookup_icon ("computer-symbolic", size,
                                                                IconLookupFlags.GENERIC_FALLBACK);
            Gdk.cairo_set_source_pixbuf (context, icon_info.load_icon (),
                                         (width - size) / 2, (height - size) / 2);
            context.rectangle ((width - size) / 2, (height - size) / 2, size, size);
            context.fill ();
            pixbuf = Gdk.pixbuf_get_from_surface (surface, 0, 0, width, height);
        } catch {
        }

        if (pixbuf != null)
            return pixbuf;

        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
        return Gdk.pixbuf_get_from_surface (surface, 0, 0, width, height);
    }

    private void update_display () {
        string type, gport, socket, ghost;

        try {
            var xmldoc = this.domain.get_config (0).doc;
            type = extract_xpath (xmldoc, "string(/domain/devices/graphics/@type)", true);
            gport = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@port)");
            socket = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@socket)");
            ghost = extract_xpath (xmldoc, @"string(/domain/devices/graphics[@type='$type']/@listen)");
        } catch (GLib.Error error) {
            warning (error.message);

            return;
        }

        if (type == "spice") {
            this.display = new SpiceDisplay (ghost, gport.to_int ());
        } else {
            warning ("unsupported display of type " + type);

            return;
        }

        this.display.show.connect ((id) => {
            this.app.ui_state = Boxes.UIState.DISPLAY;
        });

        this.display.disconnected.connect (() => {
            this.app.ui_state = Boxes.UIState.COLLECTION;
        });
    }
}

public class Boxes.BoxActor: Boxes.UI {
    public Clutter.Box actor;

    private GtkClutter.Texture screenshot;
    private GtkClutter.Actor gtkactor;
    private Gtk.Label label;
    private Gtk.VBox vbox; // and the vbox under it
    private Gtk.Entry entry;
    private Gtk.Widget? display;
    private Box box;

    // signal handler IDs
    private ulong width_req_id;
    private ulong height_req_id;

    public BoxActor (Box box) {
        this.box = box;

        var layout = new Clutter.BoxLayout ();
        layout.vertical = true;
        var cbox = new Clutter.Box (layout);

        this.screenshot = new GtkClutter.Texture ();
        this.screenshot.name = "screenshot";

        this.scale_screenshot ();
        actor_add (this.screenshot, cbox);
        this.screenshot.keep_aspect_ratio = true;

        this.vbox = new Gtk.VBox (false, 0);
        this.gtkactor = new GtkClutter.Actor.with_contents (this.vbox);
        this.label = new Gtk.Label (box.name);
        this.vbox.add (this.label);
        this.entry = new Gtk.Entry ();
        this.entry.set_visibility (false);
        this.entry.set_placeholder_text ("Password"); // TODO: i18n stupid vala...
        this.vbox.add (this.entry);

        this.vbox.show_all ();
        this.entry.hide ();

        actor_add (this.gtkactor, cbox);

        this.actor = cbox;
    }

    public void scale_screenshot (float scale = 1.5f) {
        this.screenshot.set_size (128 * scale, 96 * scale);
    }

    public void set_screenshot (Gdk.Pixbuf pixbuf) throws GLib.Error {
        this.screenshot.set_from_pixbuf (pixbuf);
    }

    public void show_display (Gtk.Widget display) {
        if (this.display != null) {
            warning ("This box actor already contains a display");
            return;
        }

        actor_remove (this.screenshot);

        this.display = display;
        this.width_req_id = display.notify["width-request"].connect ( (pspec) => {
            this.update_display_size ();
        });
        this.height_req_id = display.notify["height-request"].connect ( (pspec) => {
            this.update_display_size ();
        });
        this.vbox.add (display);
        this.update_display_size ();

        display.show ();
        display.grab_focus ();
    }

    public void hide_display () {
        if (this.display == null)
            return;

        this.vbox.remove (this.display);
        this.display.disconnect (this.width_req_id);
        this.display.disconnect (this.height_req_id);
        this.display = null;

        this.actor.pack_at (this.screenshot, 0);
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.CREDS:
            this.scale_screenshot (2.0f);
            this.entry.show ();
            // actor.entry.set_sensitive (false); FIXME: depending on spice-gtk conn. results
            this.entry.set_can_focus (true);
            this.entry.grab_focus ();

            break;

        case UIState.DISPLAY: {
            int width, height;

            this.entry.hide ();
            this.label.hide ();
            this.box.app.window.get_size (out width, out height);
            this.screenshot.animate (Clutter.AnimationMode.LINEAR, Boxes.App.duration,
                                     "width", (float) width,
                                     "height", (float) height);
            this.actor.animate (Clutter.AnimationMode.LINEAR, Boxes.App.duration,
                                "x", 0.0f,
                                "y", 0.0f);

            break;
        }

        case UIState.COLLECTION:
            this.hide_display ();
            this.scale_screenshot ();
            this.entry.set_can_focus (false);
            this.entry.hide ();
            this.label.show ();

            break;

        default:
            message ("Unhandled UI state " + ui_state.to_string ());

            break;
        }
    }

    private void update_display_size () {
        if (this.display.width_request < 320 || this.display.height_request < 200) {
            // filter invalid size request
            // TODO: where does it come from
            return;
        }

        this.box.app.set_window_size (this.display.width_request, this.display.height_request);
    }
}

