using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/index-page.ui")]
private class Boxes.AssistantIndexPage : AssistantPage {
    GLib.ListStore source_model = new GLib.ListStore (typeof (InstallerMedia));
    GLib.ListStore featured_model = new GLib.ListStore (typeof (Osinfo.Media));

    private AppWindow app_window;
    private VMAssistant dialog;

    private GLib.List<InstallerMedia> installer_medias;

    private const int MAX_MEDIA_ENTRIES = 3;

    [GtkChild]
    private Stack stack;
    [GtkChild]
    private AssistantDownloadsPage recommended_downloads_page;
    [GtkChild]
    private ScrolledWindow home_page;

    [GtkChild]
    private ListBox source_medias;
    [GtkChild]
    private ListBox featured_medias;
    [GtkChild]
    private Button expand_detected_sources_list_button;

    construct {
        populate_media_lists.begin ();

        source_medias.bind_model (source_model, add_media_entry);
        featured_medias.bind_model (featured_model, add_featured_media_entry);
    }

    public void setup (AppWindow app_window, VMAssistant dialog) {
        this.app_window = app_window;
        this.dialog = dialog;
    }

    public void go_back () {
        if (stack.visible_child == home_page) {
            dialog.close ();
        }

        stack.visible_child = home_page;
        dialog.previous_button.label = _("Cancel");
    }

    private async void populate_media_lists () {
        var media_manager = MediaManager.get_instance ();

        installer_medias = yield media_manager.list_installer_medias ();
        populate_detected_sources_list (MAX_MEDIA_ENTRIES);

        var recommended_downloads = yield get_recommended_downloads ();
        for (var i = 0; i < MAX_MEDIA_ENTRIES; i++)
            featured_model.append (recommended_downloads.nth (i).data);
    }

    private void populate_detected_sources_list (int? number_of_items = null) {
        source_model.remove_all ();

        if (number_of_items != null) {
            for (var i = 0; i < number_of_items; i++)
                source_model.append (installer_medias.nth (i).data);
        } else {
            foreach (var media in installer_medias)
                source_model.append (media);
        }
    }

    private Gtk.Widget add_media_entry (GLib.Object object) {
        return new WizardMediaEntry (object as InstallerMedia);
    }

    private Gtk.Widget add_featured_media_entry (GLib.Object object) {
        return new WizardDownloadableEntry (object as Osinfo.Media);
    }

    [GtkCallback]
    private void on_expand_detected_sources_list () {
        populate_detected_sources_list ();

        expand_detected_sources_list_button.hide ();
    }

    [GtkCallback]
    private void on_source_media_selected (Gtk.ListBoxRow row) {
        done ((row as WizardMediaEntry).media);
    }

    [GtkCallback]
    private void on_featured_media_selected (Gtk.ListBoxRow row) {
        var entry = row as WizardDownloadableEntry;

        on_download_selected (entry.url);
    }

    public override void cleanup () {
    }

    [GtkCallback]
    private async void on_select_file_button_clicked () {
        var file_chooser = new Gtk.FileChooserNative (_("Select a device or ISO file"),
                                                      app_window,
                                                      Gtk.FileChooserAction.OPEN,
                                                      _("Open"), _("Cancel"));
        if (file_chooser.run () == Gtk.ResponseType.ACCEPT) {
            var media_manager = MediaManager.get_instance ();
            var media = yield media_manager.create_installer_media_for_path (file_chooser.get_filename (),
                                                                             null); // TODO: make it cancellable
            done (media);
        }
    }

    [GtkCallback]
    private void on_download_an_os_button_clicked () {
        stack.set_visible_child (recommended_downloads_page);

        dialog.previous_button.label = _("Previous");
    }

    [GtkCallback]
    private void on_download_selected (string url) {
        print (url);
    }
}
