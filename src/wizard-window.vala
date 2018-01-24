// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private enum Boxes.WizardWindowPage {
    MAIN,
    CUSTOMIZATION,
    FILE_CHOOSER,
    DOWNLOADS,
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-window.ui")]
private class Boxes.WizardWindow : Gtk.Window, Boxes.UI {
    public const string[] page_names = { "main", "customization", "file_chooser", "downloads" };

    public delegate void FileChosenFunc (string uri);
    public delegate void DownloadChosenFunc (string uri);
    public delegate void CustomDownloadChosenFunc ();

    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private WizardWindowPage _page;
    public WizardWindowPage page {
        get { return _page; }
        set {
            if (_page == WizardWindowPage.CUSTOMIZATION && value != WizardWindowPage.CUSTOMIZATION &&
                resource_properties != null && resource_properties.length () > 0) {
                foreach (var property in resource_properties)
                    property.flush ();
                resource_properties = null;

                wizard.review.begin ();
            }

            _page = value;

            view.visible_child_name = page_names[value];
            topbar.page = value;
        }
    }

    [GtkChild]
    public Gtk.Stack view;
    [GtkChild]
    public Wizard wizard;
    [GtkChild]
    public Gtk.Grid customization_grid;
    [GtkChild]
    public Gtk.FileChooserWidget file_chooser;
    [GtkChild]
    public WizardToolbar topbar;
    [GtkChild]
    public Notificationbar notificationbar;
    [GtkChild]
    private Gtk.ListBox downloads_list;

    private GLib.List<Boxes.Property> resource_properties;

    public WizardWindow (AppWindow app_window) {
        wizard.setup_ui (app_window, this);
        topbar.setup_ui (this);

        foreach (var extension in InstalledMedia.supported_extensions)
            file_chooser.filter.add_pattern ("*" + extension);

        set_transient_for (app_window);

        notify["ui-state"].connect (ui_state_changed);

        downloads_list.set_filter_func (downloads_filter_func);
        topbar.downloads_search.search_changed.connect (() => {
            downloads_list.invalidate_filter ();
        });
    }

    public void show_customization_page (LibvirtMachine machine) {
        resource_properties = new GLib.List<Boxes.Property> ();
        machine.properties.get_resources_properties (ref resource_properties);

        return_if_fail (resource_properties.length () > 0);

        foreach (var child in customization_grid.get_children ())
            customization_grid.remove (child);

        var current_row = 0;
        foreach (var property in resource_properties) {
            if (property.widget == null || property.extra_widget == null) {
                warn_if_reached ();

                continue;
            }

            property.widget.hexpand = true;
            customization_grid.attach (property.widget, 0, current_row, 1, 1);

            property.extra_widget.hexpand = true;
            customization_grid.attach (property.extra_widget, 0, current_row + 1, 1, 1);

            current_row += 2;
        }
        customization_grid.show_all ();

        page = WizardWindowPage.CUSTOMIZATION;
    }

    public void show_file_chooser (owned FileChosenFunc file_chosen_func) {
        ulong activated_id = 0;
        activated_id = file_chooser.file_activated.connect (() => {
            var uri = file_chooser.get_uri ();
            file_chosen_func (uri);
            file_chooser.disconnect (activated_id);

            page = WizardWindowPage.MAIN;
        });
        page = WizardWindowPage.FILE_CHOOSER;
    }

    public void add_custom_download (Gtk.ListBoxRow row, owned CustomDownloadChosenFunc custom_download_chosen_func) {
        if (row.get_parent () != null)
            return;

        // TODO: insert sorted based on release date.
        downloads_list.insert (row, -1);

        var button = row.get_child () as Gtk.Button;

        ulong activated_id = 0;
        activated_id = button.clicked.connect (() => {
            custom_download_chosen_func ();
            button.disconnect (activated_id);

            page = WizardWindowPage.MAIN;
        });
    }

    public void show_downloads_page (OSDatabase os_db, owned DownloadChosenFunc download_chosen_func) {
        page = WizardWindowPage.DOWNLOADS;

        ulong activated_id = 0;
        activated_id = downloads_list.row_activated.connect ((row) => {
            var entry = row as WizardDownloadableEntry;

            download_chosen_func (entry.url);
            downloads_list.disconnect (activated_id);

            page = WizardWindowPage.MAIN;
        });
        page = WizardWindowPage.DOWNLOADS;
        topbar.downloads_search.grab_focus ();

        return_if_fail (downloads_list.get_children ().length () == 0);

        os_db.list_downloadable_oses.begin ((db, result) => {
            try {
                var media_list = os_db.list_downloadable_oses.end (result);

                foreach (var media in media_list) {
                    var entry = new WizardDownloadableEntry (media);

                    downloads_list.insert (entry, -1);
                }
            } catch (OSDatabaseError error) {
                debug ("Failed to populate the list of downloadable OSes: %s", error.message);
            }
        });
    }

    private bool downloads_filter_func (Gtk.ListBoxRow row) {
        if (topbar.downloads_search.get_text_length () == 0)
            return true;

        // FIXME: custom items should also be searchable.
        if (!(row is WizardDownloadableEntry))
            return false;

        var entry = row as WizardDownloadableEntry;
        var text = canonicalize_for_search (topbar.downloads_search.get_text ());

        return text in canonicalize_for_search (entry.title);
    }

    private void ui_state_changed () {
        wizard.set_state (ui_state);

        this.visible = (ui_state == UIState.WIZARD);
    }

    [GtkCallback]
    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        var default_modifiers = Gtk.accelerator_get_default_mod_mask ();
        var direction = get_direction ();

        if (((direction == Gtk.TextDirection.LTR && // LTR
              event.keyval == Gdk.Key.Left) ||      // ALT + Left -> back
             (direction == Gtk.TextDirection.RTL && // RTL
              event.keyval == Gdk.Key.Right)) &&    // ALT + Right -> back
            (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            topbar.click_back_button ();
            return true;
        } else if (((direction == Gtk.TextDirection.LTR && // LTR
                     event.keyval == Gdk.Key.Right) ||     // ALT + Right -> forward
                    (direction == Gtk.TextDirection.RTL && // RTL
                     event.keyval == Gdk.Key.Left)) &&     // ALT + Left -> forward
                   (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            topbar.click_forward_button ();
            return true;
        } else if (event.keyval == Gdk.Key.Escape) { // ESC -> cancel
            if (page == WizardWindowPage.MAIN)
                topbar.cancel_btn.clicked ();
            else
                page = WizardWindowPage.MAIN;

        }

        return false;
    }

    [GtkCallback]
    private bool on_delete_event () {
        wizard.cancel ();

        return true;
    }
}
