using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/index-page.ui")]
private class Boxes.AssistantIndexPage : AssistantPage {
    GLib.ListStore source_model = new GLib.ListStore (typeof (InstallerMedia));
    GLib.ListStore featured_model = new GLib.ListStore (typeof (Osinfo.Media));

    private VMAssistant dialog;

    private GLib.List<InstallerMedia> installer_medias;

    private const int MAX_MEDIA_ENTRIES = 3;

    [GtkChild]
    private unowned Stack stack;
    [GtkChild]
    private unowned AssistantDownloadsPage recommended_downloads_page;
    [GtkChild]
    private unowned ScrolledWindow home_page;
    [GtkChild]
    private unowned Hdy.PreferencesGroup detected_sources_section;
    [GtkChild]
    private unowned ListBox source_medias;
    [GtkChild]
    private unowned ListBox featured_medias;
    [GtkChild]
    private unowned Revealer panel_revealer;

    private Gtk.Button view_more_medias_button;

    private GLib.Cancellable cancellable = new GLib.Cancellable ();

    construct {
        populate_media_lists.begin ();

        source_medias.bind_model (source_model, add_media_entry);
        featured_medias.bind_model (featured_model, add_featured_media_entry);

        view_more_medias_button = new Gtk.Button () {
            visible = true,
            image = new Gtk.Image () {
                visible = true,
                icon_name = "view-more-symbolic"
            }
        };
        view_more_medias_button.clicked.connect (on_expand_detected_sources_list);
        view_more_medias_button.get_style_context ().add_class ("flat");
        source_medias.add (view_more_medias_button);

        home_page.bind_property ("min-content-height",
                                 recommended_downloads_page.scrolled_window,
                                 "min-content-height",
                                 BindingFlags.SYNC_CREATE);
    }

    public void setup (VMAssistant dialog) {
        this.dialog = dialog;
    }

    public void go_back () {
        if (stack.visible_child == home_page) {
            dialog.shutdown ();

            return;
        }

        stack.visible_child = home_page;
        update_topbar ();
    }

    private async void populate_media_lists () {
        var media_manager = MediaManager.get_default ();
        yield media_manager.connect_to_tracker ();

        installer_medias = yield media_manager.list_installer_medias ();
        populate_detected_sources_list (MAX_MEDIA_ENTRIES);

        var recommended_downloads = yield get_recommended_downloads ();
        if (recommended_downloads == null)
            return;
        for (var i = 0; (i < recommended_downloads.length ()) && (i < MAX_MEDIA_ENTRIES); i++)
            featured_model.append (recommended_downloads.nth (i).data);
    }

    private void populate_detected_sources_list (int? number_of_items = null) {
        var number_of_available_medias = installer_medias.length ();
        detected_sources_section.visible = (number_of_available_medias > 0);
        source_model.remove_all ();

        if (number_of_available_medias == 0)
            return;

        foreach (var media in installer_medias) {
            source_model.append (media);

            if (number_of_items != null && ((number_of_items -= 1) == 0))
                return;
        }
    }

    private Gtk.Widget add_media_entry (GLib.Object object) {
        return new AssistantMediaEntry.from_installer_media (object as InstallerMedia);
    }

    private Gtk.Widget add_featured_media_entry (GLib.Object object) {
        return new AssistantDownloadableEntry.from_osinfo (object as Osinfo.Media);
    }

    [GtkCallback]
    private void update_topbar () {
        dialog.previous_button.label = _("Cancel");

        var titlebar = dialog.get_titlebar () as Gtk.HeaderBar;
        if (stack.visible_child == recommended_downloads_page) {
            titlebar.set_custom_title (recommended_downloads_page.search_entry);
            panel_revealer.set_reveal_child (false);
        } else {
            titlebar.set_custom_title (null);
            panel_revealer.set_reveal_child (true);
        }
    }

    private void on_expand_detected_sources_list () {
        populate_detected_sources_list ();

        view_more_medias_button.get_parent ().destroy ();
    }

    [GtkCallback]
    private void on_source_media_selected (Gtk.ListBoxRow row) {
        var entry = row as AssistantMediaEntry;

        if (entry.media != null)
            done (entry.media);
    }

    [GtkCallback]
    private async void on_featured_media_selected (Gtk.ListBoxRow row) {
        var entry = row as AssistantDownloadableEntry;

        if (entry.os != null && entry.os.id.has_prefix ("http://redhat.com/rhel/")) {
            (new RHELDownloadDialog (dialog, entry).run ());
        } else {
            DownloadsHub.get_default ().add_item (entry);
        }

        dialog.shutdown ();
    }

    public override void cleanup () {
        cancellable.cancel ();
    }

    [GtkCallback]
    private async void on_select_file_button_clicked () {
        var file_chooser = new Gtk.FileChooserNative (_("Select a device or ISO file"),
                                                      App.app.main_window,
                                                      Gtk.FileChooserAction.OPEN,
                                                      _("Open"), _("Cancel"));
        file_chooser.bind_property ("visible", dialog, "visible", BindingFlags.INVERT_BOOLEAN);
        if (file_chooser.run () == Gtk.ResponseType.ACCEPT) {
            var media_manager = MediaManager.get_default ();
            try {
                var media = yield media_manager.create_installer_media_for_path (file_chooser.get_filename (),
                                                                                 cancellable);
                done (media);
            } catch (GLib.Error error) {
                warning ("Failed to create installer media for path '%s': %s", file_chooser.get_filename (), error.message);
            }
        }
    }

    [GtkCallback]
    private void on_download_an_os_button_clicked () {
        stack.set_visible_child (recommended_downloads_page);

        dialog.previous_button.label = _("Previous");
    }
}
