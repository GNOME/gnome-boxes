// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/downloads-hub.ui")]
private class Boxes.DownloadsHub : Gtk.Popover {
    private static DownloadsHub instance;
    public static DownloadsHub get_default () {
        if (instance == null)
            instance = new DownloadsHub ();

        return instance;
    }

    [GtkChild]
    private unowned ListBox listbox;
    private Widget button { get { return relative_to; } }

    private uint n_items = 0;
    private double progress {
        get {
            double total = 0;
            foreach (var child in listbox.get_children ()) {
                var row = child as DownloadsHubRow;
                total += row.progress.progress / n_items;
            }

            return total;
        }
    }
    private uint redraw_progress_pie_id = 0;

    private bool ongoing_downloads {
        get { return (n_items > 0); }
    }

    public void add_item (AssistantDownloadableEntry entry) {
        n_items+=1;

        var row = new DownloadsHubRow.from_entry (entry);

        if (!button.visible)
            button.visible = true;

        var bin = button as Gtk.Bin;
        var drawing_area = bin.get_child ();
        drawing_area.draw.connect (draw_button_pie);

        row.destroy.connect (on_row_deleted);
        row.download_complete.connect (on_download_complete);

        if (ongoing_downloads) {
            var reason = _("Downloading media");

            App.app.inhibit (App.app.main_window, null, reason);

            redraw_progress_pie_id = Timeout.add_seconds (1, () => {
                drawing_area.queue_draw ();

                return true;
            });
        }

        listbox.prepend (row);
        popup ();
    }

    private void on_row_deleted () {
        n_items-= 1;
        if (!ongoing_downloads) {
            // Hide the Downloads Hub when there aren't ongoing downloads
            button.visible = false;

            GLib.Source.remove (redraw_progress_pie_id);
        }
    }

    private void on_download_complete (string label, string path) {
        var msg = _("“%s” download complete").printf (label);
        var notification = new GLib.Notification (msg);
        notification.add_button (_("Install"), "app.install::" + path);

        App.app.send_notification ("downloaded-" + label, notification);

        if (!ongoing_downloads) {
            App.app.uninhibit ();
        }

        if (n_items == 1) {
            var row = listbox.get_row_at_index (0) as DownloadsHubRow;

            popdown ();
            App.app.main_window.show_vm_assistant (row.local_file);

            listbox.remove (row);
        }
    }

    [GtkCallback]
    private void on_row_activated (Gtk.ListBoxRow _row) {
        var row = _row as DownloadsHubRow;
        if (!row.complete)
            return;

        popdown ();

        if (row.local_file != null) {
            App.app.main_window.show_vm_assistant (row.local_file);
        }

        row.destroy ();
    }

    private bool draw_button_pie (Widget drawing_area, Cairo.Context context) {
        var width = drawing_area.get_allocated_width ();
        var height = drawing_area.get_allocated_height ();

        context.set_line_join (Cairo.LineJoin.ROUND);

        var style_context = button.get_style_context ();
        var foreground = style_context.get_color (button.get_state_flags ());
        var background = foreground;

        background.alpha *= 0.3;
        context.set_source_rgba (background.red, background.green, background.blue, background.alpha);
        context.arc (width / 2, height / 2, height / 3, - Math.PI / 2, 3 * Math.PI / 2);
        context.fill ();

        context.move_to (width / 2, height / 2);
        context.set_source_rgba (foreground.red, foreground.green, foreground.blue, foreground.alpha);

        double radians = - Math.PI / 2 + 2 * Math.PI * progress;
        context.arc (width / 2, height / 2, height / 3, - Math.PI / 2, radians);
        context.fill ();

        return true;
    }
}

[GtkTemplate (ui= "/org/gnome/Boxes/ui/downloads-hub-row.ui")]
private class Boxes.DownloadsHubRow : Gtk.ListBoxRow {
    [GtkChild]
    private unowned Label label;
    [GtkChild]
    private unowned Image image;
    [GtkChild]
    private unowned Stack download_status;
    [GtkChild]
    private unowned ProgressBar progress_bar;
    [GtkChild]
    private unowned Label download_complete_label;

    public ActivityProgress progress = new ActivityProgress ();
    private ulong progress_notify_id;

    private Cancellable cancellable = new Cancellable ();

    public string? local_file;

    public signal void download_complete (string label, string path);

    public bool complete = false;

    public DownloadsHubRow.from_entry (AssistantDownloadableEntry entry) {
        label.label = entry.title;

        Downloader.fetch_os_logo.begin (image, entry.os, 64);

        progress_notify_id = progress.notify["progress"].connect (() => {
            progress_bar.fraction = progress.progress;
        });
        progress_bar.fraction = progress.progress = 0;

        try {
            var download_uri = Uri.parse (entry.url, UriFlags.NONE);
            var download_path = download_uri.get_path ();
            var filename = GLib.Path.get_basename (download_path);

            download.begin (entry.url, filename);
        } catch (UriError error) {
            App.app.main_window.display_toast (new Boxes.Toast (_("Failed to download: %s").printf (error.message)));
            warning ("Failed to download '%s': %s", entry.url, error.message);
        }
    }

    private async void download (string url, string filename) {
        try {
            local_file = yield Downloader.fetch_media (url, filename, progress, cancellable);
        } catch (IOError.CANCELLED cancel_error) { // We did this, so ignore!
        } catch (GLib.Error error) {
            App.app.main_window.display_toast (new Boxes.Toast (_("Failed to download '%s': %s").printf (filename, error.message)));

            warning ("Failed to download '%s': %s", url, error.message);
            return;
        }

        if (!cancellable.is_cancelled ()) {
            complete = true;
            download_complete (label.label, local_file);
            download_status.set_visible_child (download_complete_label);
        }
    }

    [GtkCallback]
    private void cancel_download () {
        progress.disconnect (progress_notify_id);
        cancellable.cancel ();

        destroy ();
    }
}
