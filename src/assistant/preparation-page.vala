using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/preparation-page.ui")]
private class Boxes.AssistantPreparationPage : AssistantPage {
    [GtkChild]
    private Gtk.Label media_label;
    [GtkChild]
    private Gtk.Label status_label;
    [GtkChild]
    private Gtk.Image installer_image;
    [GtkChild]
    private Gtk.ProgressBar progress_bar;

    private InstallerMedia _media;
    public InstallerMedia media {
        get { return _media; }
        set {
            _media = value;

            if (_media.os != null) {
                media_label.label = _media.os.name;
                Downloader.fetch_os_logo.begin (installer_image, _media.os, 128);
            }
        }
    }

    public void setup (InstallerMedia media) {
        try {
            var media_manager = MediaManager.get_instance ();
            media = media_manager.create_installer_media_from_media (media);
        } catch (GLib.Error error) {
            warning ("Failed to setup installation media '%s': %s", media.device_file, error.message);
        }

        prepare (media);

        skip = true;
    }

    public async void prepare (InstallerMedia media) {
        var progress = create_preparation_progress ();
        if (!yield media.prepare (progress, null)) // add cancellable
            return;

        progress_bar.fraction = 1.0;

        done (media.get_vm_creator ());
    }

    private ActivityProgress create_preparation_progress () {
        var progress = new ActivityProgress ();

        progress.notify["progress"].connect (() => {
            if (progress.progress - progress_bar.fraction >= 0.01)
                progress_bar.fraction = progress.progress;
        });
        progress_bar.fraction = progress.progress = 0;

        progress.bind_property ("info", status_label, "label");

        return progress;
    }

    public override void cleanup () {
        // reset cancellation singleton
    }
}
