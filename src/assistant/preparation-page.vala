using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/preparation-page.ui")]
private class Boxes.AssistantPreparationPage : AssistantPage {
    [GtkChild]
    private unowned Gtk.Stack stack;
    [GtkChild]
    private unowned Boxes.IdentifyOsPage identify_os_page;

    [GtkChild]
    private unowned Gtk.Label media_label;
    [GtkChild]
    private unowned Gtk.Label status_label;
    [GtkChild]
    private unowned Gtk.Image installer_image;
    [GtkChild]
    private unowned Gtk.ProgressBar progress_bar;

    private Cancellable cancellable = new GLib.Cancellable ();

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

    public async void setup (InstallerMedia media, Osinfo.Os? os = null) {
        try {
            var media_manager = MediaManager.get_default ();
            this.media = media_manager.create_installer_media_from_media (media, os);
        } catch (GLib.Error error) {
            warning ("Failed to setup installation media '%s': %s", media.device_file, error.message);
        }

        if (this.media.os == null) {
            stack.visible_child = identify_os_page;
        } else {
            prepare.begin (this.media);
        }
    }

    public async override void next () {
        var os = identify_os_page.get_selected_os ();
        if (os == null) {
            prepare.begin (media);

            return;
        }

        setup.begin (media, os);
    }

    public async void prepare (InstallerMedia media) {
        skip = true;
        var progress = create_preparation_progress ();
        if (!yield media.prepare (progress, cancellable)) // add cancellable
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
        cancellable.reset ();
    }
}
