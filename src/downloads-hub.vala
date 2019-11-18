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

    // TODO: inhibit suspend

    public void add_item (WizardDownloadableEntry entry) {
        var row = new DownloadsHubRow.from_entry (entry);

        listbox.prepend (row);

        if (!relative_to.visible)
            relative_to.visible = true;

        row.destroy.connect (() => {
            if (listbox.get_children ().length () == 0)
                relative_to.visible = false;
        });

        // TODO: notify download finished
    }

    [GtkCallback]
    private void on_row_activated (Gtk.ListBoxRow _row) {
        var row = _row as DownloadsHubRow;

        if (row.local_file != null)
            App.app.main_window.show_vm_assistant (row.local_file);
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

    public DownloadsHubRow.from_entry (WizardDownloadableEntry entry) {
        label.label = entry.title;

        Downloader.fetch_os_logo.begin (image, entry.os, 64);

        progress_notify_id = progress.notify["progress"].connect (() => {
            if (progress.progress - progress_bar.fraction >= 0.01)
                progress_bar.fraction = progress.progress;
        });
        progress_bar.fraction = progress.progress = 0;

        var soup_download_uri = new Soup.URI (entry.url);
        var download_path = soup_download_uri.get_path ();

        var filename = GLib.Path.get_basename (download_path);

        download.begin (entry.url, filename);
    }

    private async void download (string url, string filename) {
        local_file = yield Downloader.fetch_media (url, filename, progress, cancellable);
    }

    [GtkCallback]
    private void cancel_download () {
        progress.disconnect (progress_notify_id);
        cancellable.cancel ();

        destroy ();
    }
}
