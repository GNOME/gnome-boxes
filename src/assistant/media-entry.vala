[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/media-entry.ui")]
private class Boxes.AssistantMediaEntry : Hdy.ActionRow {
    public InstallerMedia media;

    [GtkChild]
    protected unowned Gtk.Image media_image;

    public AssistantMediaEntry.from_installer_media (InstallerMedia media) {
        this.media = media;

        if (media.os != null)
            Downloader.fetch_os_logo.begin (media_image, media.os, 64);

        title = media.label;
        if (media.os_media != null && media.os_media.live)
            // Translators: We show 'Live' tag next or below the name of live OS media or box based on such media.
            //              http://en.wikipedia.org/wiki/Live_CD
            title += " (" +  _("Live") + ")";
        set_tooltip_text (media.device_file);

        if (media.os_media != null) {
            var architecture = (media.os_media.architecture == "i386" || media.os_media.architecture == "i686") ?
                               _("32-bit x86 system") :
                               _("64-bit x86 system");
            subtitle = architecture;

            if (media.os.vendor != null)
                // Translator comment: %s is name of vendor here (e.g Canonical Ltd or Red Hat Inc)
                subtitle += _(" from %s").printf (media.os.vendor);
        }
    }
}
