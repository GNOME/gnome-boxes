// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.Property: GLib.Object {
    public string? description { get; construct set; }
    public Gtk.Widget widget { get; construct set; }
    public Gtk.Widget? extra_widget { get; construct set; }
    public bool reboot_required { get; set; }
    public Gtk.Align description_alignment { get; set; default = Gtk.Align.END; }

    public signal void refresh_properties ();
    public signal void flushed ();

    public uint defer_interval { get; set; default = 1; } // In seconds

    public bool sensitive {
        set {
            widget.sensitive = value;
            extra_widget.sensitive = value;
        }
    }

    private uint deferred_change_id;
    private SourceFunc? _deferred_change;
    public SourceFunc? deferred_change {
        get {
            return _deferred_change;
        }

        owned set {
            if (deferred_change_id != 0) {
                Source.remove (deferred_change_id);
                deferred_change_id = 0;
            }

            _deferred_change = (owned) value;
            if (_deferred_change == null)
                return;

            if (defer_interval == 0)
                return;

            deferred_change_id = Timeout.add_seconds (defer_interval, () => {
                flush_changes ();

                return false;
            });
        }
    }

    public Property (string? description, Gtk.Widget widget, Gtk.Widget? extra_widget) {
        base (description: description, widget: widget, extra_widget: extra_widget);
    }

    public void flush () {
        flush_changes ();

        flushed ();
    }

    private void flush_changes () {
        if (deferred_change == null)
            return;

        deferred_change ();

        deferred_change = null;
    }
}

private class Boxes.SizeProperty : Boxes.Property {
    public signal void changed (uint64 value);

    private Gtk.Scale scale;
    private FormatSizeFlags format_flags;

    private static void set_size_value_label_msg (Gtk.Label       label,
                                                  uint64          size,
                                                  uint64          allocation,
                                                  FormatSizeFlags format_flags) {
        var capacity = format_size (size, format_flags);

        if (allocation == 0) {
            label.set_text (capacity);
        } else {
            var allocation_str = format_size (allocation, format_flags);

            // Translators: This is memory or disk size. E.g. "2 GB (1 GB used)".
            var label_text = _(("%s used")).printf (allocation_str);
            var markup = ("%s <span color=\"grey\">%s</span>").printf (capacity, label_text);
            label.set_markup (markup);
        }
    }

    public uint64 recommended  {
        set {
            // FIXME: Better way to ensure recommended mark is not too close to min and max marks?
            if (value < (scale.adjustment.lower + Osinfo.GIBIBYTES) ||
                value > (scale.adjustment.upper - Osinfo.GIBIBYTES))
                return;

            // Translators: This is memory or disk size. E.g. "1 GB (recommended)".
            var size = "<small>" + _("%s (recommended)").printf (format_size (value, format_flags)) + "</small>";
            scale.add_mark (value, Gtk.PositionType.BOTTOM, size);
        }
    }

    public SizeProperty (string          name,
                         uint64          size,
                         uint64          min,
                         uint64          max,
                         uint64          allocation,
                         uint64          step,
                         FormatSizeFlags format_flags) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        var name_label = new Gtk.Label.with_mnemonic (name);
        name_label.halign = Gtk.Align.START;
        name_label.get_style_context ().add_class ("dim-label");
        box.add (name_label);
        var value_label = new Gtk.Label ("");
        set_size_value_label_msg (value_label, size, allocation, format_flags);
        value_label.halign = Gtk.Align.START;
        box.add (value_label);

        var scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, min, max, step);
        name_label.mnemonic_widget = scale;

        var size_str = format_size (min, format_flags);
        size_str = "<small>" + size_str + "</small>";
        scale.add_mark (min, Gtk.PositionType.BOTTOM, size_str);

        size_str =  "<small>" + format_size (max, format_flags) + "</small>";
        scale.add_mark (max, Gtk.PositionType.BOTTOM, size_str);

        scale.set_show_fill_level (true);
        scale.set_restrict_to_fill_level (false);
        scale.set_value (size);
        scale.set_fill_level (size);
        scale.set_draw_value (false);
        scale.hexpand = true;
        scale.margin_bottom = 20;

        base (null, box, scale);

        this.scale = scale;
        this.format_flags = format_flags;

        scale.value_changed.connect (() => {
            uint64 v = (uint64) scale.get_value ();
            set_size_value_label_msg (value_label, v, allocation, format_flags);
            scale.set_fill_level (v);

            changed ((uint64) scale.get_value ());
        });
    }
}

private class Boxes.StringProperty : Boxes.Property {
    public string text {
        get { return (widget as Gtk.Label).label; }
    }

    public StringProperty (string name, string value) {
        var label = new Gtk.Label (value);
        label.halign = Gtk.Align.START;
        label.selectable = true;

        base (name, label, null);
    }
}

private class Boxes.EditableStringProperty : Boxes.Property {
    public signal void changed (string value);

    public string text {
        get { return entry.text; }
        set { entry.text = value; }
    }

    private Gtk.Entry entry;

    public EditableStringProperty (string name, string value) {
        var entry = new Gtk.Entry ();

        base (name, entry, null);
        this.entry = entry;

        entry.text = value;

        entry.notify["text"].connect (() => {
            changed (entry.text);
        });
    }
}

private interface Boxes.IPropertiesProvider: GLib.Object {
    public abstract List<Boxes.Property> get_properties (Boxes.PropertiesPage page);

    protected Boxes.Property add_property (ref List<Boxes.Property> list,
                                           string? name,
                                           Widget widget,
                                           Widget? extra_widget = null) {
        var property = new Property (name, widget, extra_widget);
        list.append (property);
        return property;
    }

    protected Boxes.StringProperty add_string_property (ref List<Boxes.Property> list,
                                                        string                   name,
                                                        string                   value) {
        var property = new StringProperty (name, value);
        list.append (property);

        return property;
    }

    protected Boxes.EditableStringProperty add_editable_string_property (ref List<Boxes.Property> list,
                                                                         string                   name,
                                                                         string                   value) {
        var property = new EditableStringProperty (name, value);
        list.append (property);

        return property;
    }

    protected Boxes.SizeProperty add_size_property (ref List<Boxes.Property> list,
                                                    string                   name,
                                                    uint64                   size,
                                                    uint64                   min,
                                                    uint64                   max,
                                                    uint64                   allocation,
                                                    uint64                   step,
                                                    FormatSizeFlags          format_flags = FormatSizeFlags.DEFAULT) {
        var property = new SizeProperty (name, size, min, max, allocation, step, format_flags);
        list.append (property);

        return property;
    }
}

