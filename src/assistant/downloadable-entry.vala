private class Boxes.AssistantDownloadableEntry : Boxes.AssistantMediaEntry {
    public Osinfo.Os? os;
    public string url;

    public AssistantDownloadableEntry.from_osinfo (Osinfo.Media media) {
        this.os = media.os;

        url = media.url;

        title = media.get_data ("title") ?? serialize_os_title (media);
        subtitle = media.get_data ("subtitle") ??  media.os.vendor;
        set_tooltip_text (media.url ?? title);

        Downloader.fetch_os_logo.begin (media_image, os, 64);
    }
}
