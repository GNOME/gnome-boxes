// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

public delegate void PropertyStringChanged (string value) throws Boxes.Error;
public delegate void PropertySizeChanged (uint64 value) throws Boxes.Error;

private interface Boxes.IPropertiesProvider: GLib.Object {
    public abstract List<Pair<string, Widget>> get_properties (Boxes.PropertiesPage page);

    protected void add_property (ref List<Pair<string, Widget>> list, string name, Widget widget) {
        list.append (new Pair<string, Widget> (name, widget));
    }

    protected void add_string_property (ref List<Pair<string, Widget>> list,
                                        string                         name,
                                        string                         value,
                                        PropertyStringChanged?         changed = null) {
        var entry = new Boxes.EditableEntry ();

        entry.text = value;
        entry.selectable = true;
        entry.editable = changed != null;

        entry.editing_done.connect (() => {
            try {
                changed (entry.text);
            } catch (Boxes.Error.INVALID error) {
                entry.start_editing ();
            } catch (Boxes.Error error) {
                warning (error.message);
            }
        });

        add_property (ref list, name, entry);
    }

    protected void add_size_property (ref List<Pair<string, Widget>> list,
                                      string                         name,
                                      uint64                         size,
                                      uint64                         min,
                                      uint64                         max,
                                      uint64                         step,
                                      PropertySizeChanged?           changed = null) {
        var scale = new Gtk.HScale.with_range (min, max, step);

        scale.format_value.connect ((scale, value) => {
            return format_size (((uint64) value) * Osinfo.KIBIBYTES, FormatSizeFlags.IEC_UNITS);
        });

        scale.set_value (size);
        scale.hexpand = true;
        scale.vexpand = true;
        scale.margin_bottom = 20;

        if (changed != null)
            scale.value_changed.connect (() => {
                try {
                    changed ((uint64) scale.get_value ());
                } catch (Boxes.Error error) {
                    warning (error.message);
                }
            });

        add_property (ref list, name, scale);
    }
}

