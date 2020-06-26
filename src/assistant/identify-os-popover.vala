// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/identify-os-popover.ui")]
public class Boxes.IdentifyOsPopover : Gtk.Popover {
    [GtkChild]
    private Gtk.SearchEntry search_entry;
    [GtkChild]
    private Gtk.ListBox listbox;
    private GLib.ListStore model;

    private GLib.List<weak Osinfo.Entity> os_list;

    public signal void os_selected (Osinfo.Os? os);

    private Gtk.ListBoxRow? previous_row = null;

    public IdentifyOsPopover () {
        search_entry.grab_focus ();

        setup_model.begin ();
    }

    private async void setup_model () {
        var media_manager = MediaManager.get_instance ();

        os_list = yield media_manager.os_db.get_all_oses_sorted_by_release_date ();
        model = new GLib.ListStore (typeof (Osinfo.Os));

        yield purge_model ();
        listbox.bind_model (model, create_listbox_entry);
    }

    private Gtk.Widget create_listbox_entry (Object item) {
        var os_item = item as Osinfo.Os;

        return new OsListEntry (os_item);
    }

    private async void purge_model () {
        model.remove_all ();

        foreach (var media in yield get_recommended_downloads ()) {
            if (media != null) {
                model.append (media.os);
            }
        }
    }

    [GtkCallback]
    private async void on_search_entry_changed () {
        var text = search_entry.get_text ();
        if (text.length == 0) {
            yield purge_model ();

            return;
        } else {
            model.remove_all ();
        }

        listbox.select_row (null);

        var query = canonicalize_for_search (text);
        var nresults = 6;
        foreach (var entity in os_list) {
            if (nresults == 0)
                return;

            var os = entity as Osinfo.Os;
            var os_name = os.get_name ();
            if (os_name == null)
                continue;

            var name = canonicalize_for_search (os_name);
            if (query in name) {
                model.append (os);

                nresults -= 1;
            }
        }
    }

    [GtkCallback]
    private void on_listbox_row_activated (Gtk.ListBoxRow row) {
        if (row != previous_row) {
            previous_row = row;

            return;
        }

        listbox.unselect_row (row);
        previous_row = null;

        var child = row.get_child () as OsListEntry;
        child.selected = false;

        os_selected (null);
    }

    [GtkCallback]
    private void on_listbox_row_selected () {
        var row = listbox.get_selected_row ();
        if (row == null)
            return;

        foreach (var widget in listbox.get_children ()) {
            var entry = widget as Gtk.ListBoxRow;
            var child = entry.get_child () as OsListEntry;

            child.selected = false;
        }

        var os_list_entry = row.get_child () as OsListEntry;
        os_list_entry.selected = true;

        os_selected (os_list_entry.os);
    }
}

class OsListEntry : Gtk.Box {
    public Osinfo.Os os;

    public bool selected {
        set {
            image.visible = value;
        }

        get {
            return image.visible;
        }
    }

    private Gtk.Label label = new Gtk.Label (null) {
        margin = 5,
        halign = Gtk.Align.START,
        xalign = 0,
        visible = true
    };

    private Gtk.Image image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.MENU);

    public OsListEntry (Osinfo.Os os) {
        this.os = os;

        var os_name = os.get_name ();
        if (os_name != null) {
            label.label = os_name.replace ("Unknown", "");
            visible = true;
        }
        add (label);

        add (image);
        image.visible = false;
    }
}
