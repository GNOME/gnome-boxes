// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/os-downloader.ui")]
private class Boxes.OsDownloader : Hdy.PreferencesWindow {
    private OSDatabase os_db = new OSDatabase ();

    [GtkChild]
    private unowned Hdy.PreferencesGroup recommended_downloads;
    [GtkChild]
    private unowned Hdy.PreferencesGroup all_downloads;

    construct {
        os_db.load.begin ();
    }

    public OsDownloader (AppWindow window) {
        set_transient_for (window);

        populate.begin ();
    }

    private Boxes.AssistantDownloadableEntry create_entry_from_media (Osinfo.Media media) {
        var entry = new Boxes.AssistantDownloadableEntry.from_osinfo (media);
        entry.activated.connect (on_os_entry_activated);

        return entry;
    }

    private async void populate () {
        foreach (var media in yield fetch_recommended_downloads_from_net ()) {
            if (media != null) {
                recommended_downloads.add (create_entry_from_media (media));
            }
        }

        try {
            var manager = MediaManager.get_default ();
            var os_list = yield manager.os_db.list_downloadable_oses ();

            foreach (var media in os_list) {
                if (media != null) {
                    all_downloads.add (create_entry_from_media (media)); 
                }
            }
        } catch (GLib.Error error) {
            warning ("Failed to obtain list of downloadable OSes: %s", error.message);
            return;
        }

    }

    private async void on_os_entry_activated (Hdy.ActionRow row) {
        var entry = row as AssistantDownloadableEntry;
        if (entry.os == null)
            return;

        hide ();
        if (entry.os.id.has_prefix ("http://redhat.com/rhel/")) {
            // FIXME: port this away from GtkDialog
            (new RHELDownloadDialog (entry)).run ();
        } else {
            // FIXME: the popover blocks the window close call bellow
            DownloadsHub.get_default ().add_item (entry);
        }

        close ();
    }
}
