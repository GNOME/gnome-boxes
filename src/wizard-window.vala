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

    public HashTable<string,Osinfo.Os> logos_table;

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
    public WizardDownloadsPage downloads_page;
    [GtkChild]
    public Gtk.Grid customization_grid;
    [GtkChild]
    public Gtk.FileChooserWidget file_chooser;
    [GtkChild]
    public WizardToolbar topbar;
    [GtkChild]
    public Notificationbar notificationbar;

    private GLib.List<Boxes.Property> resource_properties;

    public WizardWindow (AppWindow app_window) {
        wizard.setup_ui (app_window, this);
        topbar.setup_ui (this);

        foreach (var extension in InstalledMedia.supported_extensions)
            file_chooser.filter.add_pattern ("*" + extension);

        set_transient_for (app_window);

        notify["ui-state"].connect (ui_state_changed);

        topbar.downloads_search.search_changed.connect (() => {
            var text = topbar.downloads_search.get_text ();

            if (text == null)
                return;

            downloads_page.search.text = text;
        });

        topbar.downloads_search.activate.connect (() => {
            var text = topbar.downloads_search.get_text ();

            if (text == null)
                return;

            var scheme = Uri.parse_scheme (text);
            if (scheme != null && scheme in Downloader.supported_schemes) {
                wizard.open_with_uri (text);
                page = WizardWindowPage.MAIN;
            }
        });

        logos_table = new HashTable<string, Osinfo.Os> (str_hash, str_equal);
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

    public void show_downloads_page (OSDatabase os_db, owned DownloadChosenFunc download_chosen_func) {
        page = WizardWindowPage.DOWNLOADS;
        topbar.downloads_search.grab_focus ();

        downloads_page.download_chosen_func = (owned) download_chosen_func;
        downloads_page.page = WizardDownloadsPageView.RECOMMENDED;

        os_db.list_downloadable_oses.begin ((db, result) => {
            try {
                var media_list = os_db.list_downloadable_oses.end (result);

                foreach (var media in media_list) {
                    logos_table.insert (media.url, media.os);
                }
            } catch (OSDatabaseError error) {
                debug ("Failed to populate the list of downloadable OSes: %s", error.message);
            }
        });
    }

    public Osinfo.Os? get_os_from_uri (string uri) {
       return logos_table.lookup (uri);
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
