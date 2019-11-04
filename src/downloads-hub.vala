// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/downloads-hub.ui")]
private class Boxes.DownloadsHub : Gtk.Popover {
    private static DownloadsHub instance;
    public static DownloadsHub get_instance () {
        if (instance == null)
            instance = new DownloadsHub ();

        return instance;
    }

    [GtkChild]
    private ListBox listbox;

    private bool ongoing_downloads {
        get { return (listbox.get_children ().length () > 0); }
    }

    // TODO: inhibit suspend

    public void add_item (WizardDownloadableEntry entry) {
        var row = new DownloadsHubRow.from_entry (entry);

        if (!relative_to.visible)
            relative_to.visible = true;

        row.destroy.connect (on_row_deleted);
        row.download_complete.connect (on_download_complete);

        if (!ongoing_downloads) {
            var reason = _("Downloading media");

            App.app.inhibit (App.app.main_window, null, reason);
        }

        listbox.prepend (row);
    }

    private void on_row_deleted () {
        if (!ongoing_downloads) {
            // Hide the Downloads Hub when there aren't ongoing downloads
            relative_to.visible = false;
        }
    }

    private void on_download_complete (string label, string path) {
        var msg = _("“%s“ download complete").printf (label);
        var notification = new GLib.Notification (msg);
        notification.add_button (_("Install"), "app.install::" + path);

        App.app.send_notification ("downloaded-" + label, notification);

        if (!ongoing_downloads) {
            App.app.uninhibit ();
        }
    }

    [GtkCallback]
    private void on_row_activated (Gtk.ListBoxRow _row) {
        var row = _row as DownloadsHubRow;

        if (row.local_file != null) {
            App.app.main_window.show_vm_assistant (row.local_file);

            popup ();
        }
    }
}

[GtkTemplate (ui= "/org/gnome/Boxes/ui/downloads-hub-row.ui")]
private class Boxes.DownloadsHubRow : Gtk.ListBoxRow {
    [GtkChild]
    private Label label;
    [GtkChild]
    private Image image;
    [GtkChild]
    private ProgressBar progress_bar;

    private ActivityProgress progress = new ActivityProgress ();
    private ulong progress_notify_id;

    private Cancellable cancellable = new Cancellable ();

    public string? local_file;

    public signal void download_complete (string label, string path);

    public DownloadsHubRow.from_entry (WizardDownloadableEntry entry) {
        label.label = entry.title;

        Downloader.fetch_os_logo.begin (image, entry.os, 64);

        progress_notify_id = progress.notify["progress"].connect (() => {
            progress_bar.fraction = progress.progress;
        });
        progress_bar.fraction = progress.progress = 0;

        var soup_download_uri = new Soup.URI (entry.url);
        var download_path = soup_download_uri.get_path ();

        var filename = GLib.Path.get_basename (download_path);

        download.begin (entry.url, filename);
    }

    private async void download (string url, string filename) {
        try {
            local_file = yield Downloader.fetch_media (url, filename, progress, cancellable);
        } catch (IOError.CANCELLED cancel_error) { // We did this, so ignore!
        } catch (GLib.Error error) {
            App.app.main_window.notificationbar.display_error (_("Failed to download"));

            warning (error.message);
            return;
        }

        download_complete (label.label, local_file);
    }

    [GtkCallback]
    private void cancel_download () {
        progress.disconnect (progress_notify_id);
        cancellable.cancel ();

        destroy ();
    }
}
