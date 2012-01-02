// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

public delegate void PropertyStringChanged (string value) throws Boxes.Error;

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
            } catch (Boxes.Error error) {
                warning (error.message);
            }
        });

        add_property (ref list, name, entry);
    }
}

