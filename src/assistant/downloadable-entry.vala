[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/downloadable-entry.ui")]
public class Boxes.AssistantDownloadableEntry : Gtk.ListBoxRow {
    public Osinfo.Os? os;

    [GtkChild]
    private unowned Gtk.Image media_image;
    [GtkChild]
    private unowned Gtk.Label title_label;
    [GtkChild]
    private unowned Gtk.Label details_label;

    public string title {
        get { return title_label.get_text (); }
        set { title_label.label = value; }
    }

    public string details {
        get { return details_label.get_text (); }
        set { details_label.label = value; }
    }
    public string url;

    public AssistantDownloadableEntry (Osinfo.Media media) {
        this.from_os (media.os);

        title = serialize_os_title (media);
        details = media.os.vendor;
        set_tooltip_text (media.url ?? title);

        url = media.url;
    }

    public AssistantDownloadableEntry.from_os (Osinfo.Os os) {
        Downloader.fetch_os_logo.begin (media_image, os, 64);

        this.os = os;
    }
}
