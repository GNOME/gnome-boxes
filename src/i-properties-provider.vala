// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.Property: GLib.Object {
    public string? description { get; construct set; }
    public Gtk.Widget widget { get; construct set; }
    public Gtk.Widget? extra_widget { get; construct set; }
    public bool reboot_required { get; set; }

    public signal void refresh_properties ();

    public uint defer_interval { get; set; default = 1; } // In seconds

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

            deferred_change_id = Timeout.add_seconds (defer_interval, () => {
                flush ();

                return false;
            });
        }
    }

    public Property (string? description, Gtk.Widget widget, Gtk.Widget? extra_widget) {
        base (description: description, widget: widget, extra_widget: extra_widget);
    }

    public void flush () {
        if (deferred_change == null)
            return;

        deferred_change ();

        deferred_change = null;
    }
}

private class Boxes.SizeProperty : Boxes.Property {
    public signal void changed (uint64 value);

    public SizeProperty (string name, uint64 size, uint64 min, uint64 max, uint64 step) {
        var label = new Gtk.Label (format_size (((uint64) size) * Osinfo.KIBIBYTES, FormatSizeFlags.IEC_UNITS));
        label.halign = Gtk.Align.CENTER;

        var scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, min, max, step);

        scale.add_mark (min, Gtk.PositionType.BOTTOM, format_size (min * Osinfo.KIBIBYTES, FormatSizeFlags.IEC_UNITS));
        scale.add_mark (max, Gtk.PositionType.BOTTOM,
                        "%s (maximum)".printf (format_size (max * Osinfo.KIBIBYTES, FormatSizeFlags.IEC_UNITS)));

        scale.set_show_fill_level (true);
        scale.set_restrict_to_fill_level (false);
        scale.set_value (size);
        scale.set_fill_level (size);
        scale.set_draw_value (false);
        scale.hexpand = true;
        scale.margin_bottom = 20;

        base (name, label, scale);

        scale.value_changed.connect (() => {
            uint64 v = (uint64) scale.get_value ();
            label.set_text (format_size (v * Osinfo.KIBIBYTES, FormatSizeFlags.IEC_UNITS));
            scale.set_fill_level (v);

            changed ((uint64) scale.get_value ());
        });
    }
}

private class Boxes.StringProperty : Boxes.Property {
    public signal bool changed (string value);

    public bool editable {
        get { return entry.editable; }
        set { entry.editable = value; }
    }

    private Boxes.EditableEntry entry;

    public StringProperty (string name, string value) {
        var entry = new Boxes.EditableEntry ();

        base (name, entry, null);
        this.entry = entry;

        entry.text = value;
        entry.selectable = true;

        entry.editing_done.connect (() => {
            if (!changed (entry.text))
                entry.start_editing ();
        });
    }
}

[Flags]
public enum PropertyCreationFlag {
    NONE = 0,
    NO_USB = 1<<0
}

private interface Boxes.IPropertiesProvider: GLib.Object {
    public abstract List<Boxes.Property> get_properties (Boxes.PropertiesPage page, PropertyCreationFlag flags);

    protected Boxes.Property add_property (ref List<Boxes.Property> list, string? name, Widget widget, Widget? extra_widget = null) {
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

    protected Boxes.SizeProperty add_size_property (ref List<Boxes.Property> list,
                                                    string                   name,
                                                    uint64                   size,
                                                    uint64                   min,
                                                    uint64                   max,
                                                    uint64                   step) {
        var property = new SizeProperty (name, size, min, max, step);
        list.append (property);

        return property;
    }
}

