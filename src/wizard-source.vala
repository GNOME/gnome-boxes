// This file is part of GNOME Boxes. License: LGPLv2+

private enum Boxes.SourcePage {
    MAIN,
    URL,

    LAST,
}

public delegate bool ClickedFunc ();

/* Subclass of ScrolledWindow that shows at allocates enough
   space to not scroll for at most N children. */
[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-scrolled.ui")]
private class Boxes.WizardScrolled : Gtk.ScrolledWindow {
    [GtkChild]
    public Gtk.Box vbox;

    private int num_visible;

    // Ideally, we shouldn't need this fuction but is there a way to connect
    // vscrollbar signals from the UI template?
    public void setup (int num_visible) {
        this.num_visible = num_visible;

        notify["num-visible"].connect (() => {
            queue_resize ();
        });
        get_vscrollbar ().show.connect (() => {
            this.get_style_context ().add_class ("boxes-menu-scrolled");
            this.reset_style ();
        });
        get_vscrollbar ().hide.connect ( () => {
            this.get_style_context ().remove_class ("boxes-menu-scrolled");
            this.reset_style ();
        });
    }

    public override void get_preferred_height (out int minimum_height, out int natural_height) {
        base.get_preferred_height (out minimum_height, out natural_height);
        var viewport = get_child () as Gtk.Viewport;
        var box = viewport.get_child () as Gtk.Box;

        int height = 0;
        int i = 0;
        foreach (var w in box.get_children ()) {
            if (!w.get_visible ())
                continue;
            int child_height;
            w.get_preferred_height (null, out child_height);
            height += child_height;
            i++;
            if (i == num_visible)
                break;
        }
        minimum_height = int.max (minimum_height, height);
        natural_height = int.max (natural_height, height);
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-media-entry.ui")]
private class Boxes.WizardMediaEntry : Gtk.Button {
    public InstallerMedia media;

    [GtkChild]
    private Gtk.Image media_image;
    [GtkChild]
    private Gtk.Label title_label;
    [GtkChild]
    private Gtk.Label details_label;

    public WizardMediaEntry (InstallerMedia media) {
        this.media = media;

        if (media.os != null)
            Downloader.fetch_os_logo.begin (media_image, media.os, 64);

        title_label.label = media.label;
        if (media.os_media != null && media.os_media.live)
            // Translators: We show 'Live' tag next or below the name of live OS media or box based on such media.
            //              http://en.wikipedia.org/wiki/Live_CD
            title_label.label += " (" +  _("Live") + ")";

        if (media.os_media != null) {
            var architecture = (media.os_media.architecture == "i386" || media.os_media.architecture == "i686") ?
                               _("32-bit x86 system") :
                               _("64-bit x86 system");
            details_label.label = architecture;

            if (media.os.vendor != null)
                // Translator comment: %s is name of vendor here (e.g Canonical Ltd or Red Hat Inc)
                details_label.label += _(" from %s").printf (media.os.vendor);
        }
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-source.ui")]
private class Boxes.WizardSource: Gtk.Notebook {
    public Gtk.Widget? selected { get; set; }
    public string uri {
        get { return url_entry.get_text (); }
        set { url_entry.set_text (value); }
    }
    public InstallerMedia? install_media { get; private set; }
    public LibvirtSystemImporter libvirt_sys_importer { get; private set; }
    public bool libvirt_sys_import;

    public signal void activated (); // Emitted on user activating a source

    [GtkChild]
    private Gtk.Box main_vbox;
    [GtkChild]
    private Boxes.WizardScrolled media_scrolled;
    [GtkChild]
    private Gtk.Label url_description_label;
    [GtkChild]
    private Gtk.Image url_image;
    [GtkChild]
    private Gtk.Alignment url_entry_bin;
    [GtkChild]
    public Gtk.Entry url_entry;
    [GtkChild]
    private Gtk.Button select_file_button;
    [GtkChild]
    private Gtk.Button libvirt_sys_import_button;
    [GtkChild]
    private Gtk.Label libvirt_sys_import_label;

    private Gtk.Box media_vbox;

    public MediaManager media_manager;

    construct {
        media_manager = MediaManager.get_instance ();
        main_vbox.grab_focus ();

        media_scrolled.setup (5);
        media_vbox = media_scrolled.vbox;
        draw_as_css_box (url_entry_bin);

        update_libvirt_sytem_entry_visibility.begin ();
        add_media_entries.begin ();
    }

    [GtkCallback]
    private void on_enter_url_button_clicked () {
        page = SourcePage.URL;
    }

    [GtkCallback]
    private void on_url_back_button_clicked () {
        selected = null;
        page = SourcePage.MAIN;
    }

    [GtkCallback]
    private void on_switch_page (Gtk.Notebook self, Gtk.Widget page, uint page_num) {
        if (selected != null)
            selected.grab_focus ();
        switch (page_num) {
        case SourcePage.MAIN:
            add_media_entries.begin ();
            // FIXME: grab first element in the menu list
            main_vbox.grab_focus ();
            break;
        case SourcePage.URL:
            url_entry.changed ();
            url_entry.grab_focus ();
            break;
        }
    }

    public void update_url_page(string title, string text, string icon_name) {
        url_description_label.set_markup ("<b>"  + title + "</b>\n\n" + text);
        url_image.icon_name = icon_name;
    }

    private async void add_media_entries () {
        var medias = yield media_manager.list_installer_medias ();

        foreach (var child in media_vbox.get_children ()) {
            var child_media = (child as WizardMediaEntry).media;

            var obsolete = true;
            foreach (var media in medias)
                if (child_media.device_file == media.device_file) {
                    obsolete = false;

                    break;
                }

            if (obsolete)
                media_vbox.remove (child);
        }

        foreach (var media in medias) {
            var nouveau = true; // Everyone speaks some French, right? :)
            foreach (var child in media_vbox.get_children ()) {
                var child_media = (child as WizardMediaEntry).media;
                if (child_media.device_file == media.device_file) {
                    nouveau = false;

                    break;
                }
            }

            if (nouveau)
                add_media_entry (media);
        }

        // In case we removed everything
        if (media_vbox.get_children ().length () == 0)
            media_scrolled.hide ();
    }

    private void add_media_entry (InstallerMedia media) {
        var entry = new WizardMediaEntry (media);
        media_vbox.add (entry);
        entry.clicked.connect (() => {
            on_media_selected (media);

            selected = entry;
        });

        media_vbox.show_all ();
        media_scrolled.show ();
    }

    private async void update_libvirt_sytem_entry_visibility () {
        try {
            libvirt_sys_importer = yield new LibvirtSystemImporter ();
        } catch (LibvirtSystemImporterError.NO_IMPORTS error) {
            debug ("%s", error.message);

            return;
        }
        libvirt_sys_import_label.label = libvirt_sys_importer.wizard_menu_label;
        main_vbox.show_all ();
    }

    [GtkCallback]
    private void on_select_file_button_clicked () {
        var dialog = new Gtk.FileChooserDialog (_("Select a device or ISO file"),
                                                App.window,
                                                Gtk.FileChooserAction.OPEN,
                                                _("_Cancel"), Gtk.ResponseType.CANCEL,
                                                _("_Open"), Gtk.ResponseType.ACCEPT);
        dialog.show_hidden = false;
        dialog.filter = new Gtk.FileFilter ();
        dialog.filter.add_mime_type ("application/x-cd-image");
        foreach (var extension in InstalledMedia.supported_extensions)
            dialog.filter.add_pattern ("*" + extension);
        if (dialog.run () == Gtk.ResponseType.ACCEPT) {
            uri = dialog.get_uri ();
            // clean install_media as this may be set already when going back in the wizard
            install_media = null;
            activated ();

            selected = select_file_button;
        }

        dialog.destroy ();
    }

    [GtkCallback]
    private void on_libvirt_sys_import_button_clicked () {
        libvirt_sys_import = true;
        activated ();

        selected = libvirt_sys_import_button;
    }

    private void on_media_selected (InstallerMedia media) {
        try {
            install_media = media_manager.create_installer_media_from_media (media);
            uri = media.device_file;
            activated ();
        } catch (GLib.Error error) {
            // This is unlikely to happen since media we use as template should have already done most async work
            warning ("Failed to setup installation media '%s': %s", media.device_file, error.message);
        }
    }
}
