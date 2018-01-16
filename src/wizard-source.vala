// This file is part of GNOME Boxes. License: LGPLv2+

private enum Boxes.SourcePage {
    MAIN,
    RHEL_WEB_VIEW,
    URL,
    DOWNLOADS,

    LAST,
}

public delegate bool ClickedFunc ();

/* Subclass of ScrolledWindow that shows at allocates enough
   space to not scroll for at most N children. */
[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-scrolled.ui")]
private class Boxes.WizardScrolled : Gtk.ScrolledWindow {
    [GtkChild]
    public Gtk.ListBox vbox;

    private int num_visible { get; set; }

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

        int height = 0;
        int i = 0;
        foreach (var w in vbox.get_children ()) {
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

private class Boxes.WizardDownloadableMediaEntry : Gtk.ListBoxRow {
    public Osinfo.Media media;

    private Gtk.Label label;

    public WizardDownloadableMediaEntry (Osinfo.Media media) {
        this.media = media;

        setup_label ();
        add (label);

        this.get_style_context ().add_class ("boxes-menu-row");
        this.get_style_context ().add_class ("boxes-menu-subrow");
    }

    private void setup_label () {
        /* Libosinfo lacks some OS variant names, so we do some
           parsing here to compose a unique human-readable media
           identifier. */
        label = new Gtk.Label ("");

        var variant = "";
        var variants = media.get_os_variants ();
        if (variants.get_length () > 0)
            variant = (variants.get_nth (0) as Osinfo.OsVariant).get_name ();
        else if ((media.os as Osinfo.Product).name != null) {
            variant = (media.os as Osinfo.Product).name;
            if (media.url.contains ("server"))
                variant += " Server";
        } else {
            var file = File.new_for_uri (media.url);

            label.label = file.get_basename ().replace ("_", "");
        }

        var subvariant = "";
        if (media.url.contains ("netinst"))
            subvariant = "(netinst)";
        else if (media.url.contains ("minimal"))
            subvariant = "(minimal)";
        else if (media.url.contains ("dvd"))
            subvariant = "(DVD)";

        var is_live = media.live ? " (" + _("Live") + ")" : "";

        label.label = @"$variant $(media.architecture) $subvariant $is_live";

        /* Strip consequent whitespaces */
        label.label = label.label.replace ("  ", "");

        label.halign = Gtk.Align.START;
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-downloadable-entry.ui")]
private class Boxes.WizardDownloadableEntry : Gtk.ListBoxRow {
    [GtkChild]
    private Gtk.Image media_image;
    [GtkChild]
    private Gtk.Label title_label;
    [GtkChild]
    private Gtk.Label details_label;
    [GtkChild]
    private Gtk.Revealer revealer;
    [GtkChild]
    private Gtk.ListBox medias_listbox;

    public Osinfo.Media single_media;

    public signal void activated (Osinfo.Media media);

    public WizardDownloadableEntry (Osinfo.Os os) {
        Downloader.fetch_os_logo.begin (media_image, os, 64);

        title_label.label = os.name;
        details_label.label = os.vendor;

        var media_list = os.get_media_list () as Osinfo.List;
        if (media_list.get_length () == 1)
            single_media = media_list.get_nth (0) as Osinfo.Media;
        else
            populate_media_listbox (media_list);
    }

    private void populate_media_listbox (Osinfo.List media_list) {
        foreach (var media_entity in media_list.get_elements()) {
            var media = (media_entity as Osinfo.Media);

            medias_listbox.insert (new WizardDownloadableMediaEntry (media), -1);
        }

        medias_listbox.show_all ();
    }

    [GtkCallback]
    private void on_media_listbox_activated (Gtk.ListBoxRow row) {
        var entry = row as WizardDownloadableMediaEntry;

        activated (entry.media);
    }

    public void toggle () {
        revealer.set_reveal_child (!revealer.child_revealed);
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-media-entry.ui")]
private class Boxes.WizardMediaEntry : Gtk.ListBoxRow {
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

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-web-view.ui")]
private class Boxes.WizardWebView : Gtk.Bin {
    [GtkChild]
    private Gtk.ProgressBar progress_bar;
    [GtkChild]
    private WebKit.WebView web_view;

    private uint hide_progress_bar_id;
    private const uint progress_bar_id_timeout = 500;  // 500ms

    construct {
        var context = web_view.get_context ();
        var language_names = GLib.Intl.get_language_names ();
        context.set_preferred_languages (language_names);
    }

    public WebKit.WebView view {
        get { return web_view; }
    }

    public override void dispose () {
        if (hide_progress_bar_id != 0) {
            GLib.Source.remove (hide_progress_bar_id);
            hide_progress_bar_id = 0;
        }

        base.dispose ();
    }

    [GtkCallback]
    private bool on_context_menu (WebKit.WebView web_view,
                                  WebKit.ContextMenu context_menu,
                                  Gdk.Event event,
                                  WebKit.HitTestResult hit_test_result) {
        var items_to_remove = new GLib.List<WebKit.ContextMenuItem> ();

        foreach (var item in context_menu.get_items ()) {
            var action = item.get_stock_action ();
            if (action == WebKit.ContextMenuAction.GO_BACK ||
                action == WebKit.ContextMenuAction.GO_FORWARD ||
                action == WebKit.ContextMenuAction.DOWNLOAD_AUDIO_TO_DISK ||
                action == WebKit.ContextMenuAction.DOWNLOAD_IMAGE_TO_DISK ||
                action == WebKit.ContextMenuAction.DOWNLOAD_LINK_TO_DISK ||
                action == WebKit.ContextMenuAction.DOWNLOAD_VIDEO_TO_DISK ||
                action == WebKit.ContextMenuAction.OPEN_AUDIO_IN_NEW_WINDOW ||
                action == WebKit.ContextMenuAction.OPEN_FRAME_IN_NEW_WINDOW ||
                action == WebKit.ContextMenuAction.OPEN_IMAGE_IN_NEW_WINDOW ||
                action == WebKit.ContextMenuAction.OPEN_LINK_IN_NEW_WINDOW ||
                action == WebKit.ContextMenuAction.OPEN_VIDEO_IN_NEW_WINDOW ||
                action == WebKit.ContextMenuAction.RELOAD ||
                action == WebKit.ContextMenuAction.STOP) {
                items_to_remove.prepend (item);
            }
        }

        foreach (var item in items_to_remove) {
            context_menu.remove (item);
        }

        var separators_to_remove = new GLib.List<WebKit.ContextMenuItem> ();
        WebKit.ContextMenuAction previous_action = WebKit.ContextMenuAction.NO_ACTION; // same as a separator

        foreach (var item in context_menu.get_items ()) {
            var action = item.get_stock_action ();
            if (action == WebKit.ContextMenuAction.NO_ACTION && action == previous_action)
                separators_to_remove.prepend (item);

            previous_action = action;
        }

        foreach (var item in separators_to_remove) {
            context_menu.remove (item);
        }

        var n_items = context_menu.get_n_items ();
        return n_items == 0;
    }

    [GtkCallback]
    private void on_notify_estimated_load_progress () {
        if (hide_progress_bar_id != 0) {
            GLib.Source.remove (hide_progress_bar_id);
            hide_progress_bar_id = 0;
        }

        string? uri = web_view.get_uri ();
        if (uri == null || uri == "about:blank")
            return;

        var progress = web_view.get_estimated_load_progress ();
        bool loading = web_view.is_loading;

        if (progress == 1.0 || !loading) {
            hide_progress_bar_id = GLib.Timeout.add (progress_bar_id_timeout, () => {
                progress_bar.hide ();
                hide_progress_bar_id = 0;
                return GLib.Source.REMOVE;
            });
        } else {
            progress_bar.show ();
        }

        progress_bar.set_fraction (loading || progress == 1.0 ? progress : 0.0);
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-source.ui")]
private class Boxes.WizardSource: Gtk.Stack {
    private const string[] page_names = { "main-page", "rhel-web-view-page", "url-page", "download-an-os-page" };

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
    private Gtk.Box url_entry_vbox;
    [GtkChild]
    public Gtk.Entry url_entry;
    [GtkChild]
    private Gtk.Button select_file_button;
    [GtkChild]
    private Gtk.Button libvirt_sys_import_button;
    [GtkChild]
    private Gtk.Label libvirt_sys_import_label;
    [GtkChild]
    private Gtk.ListBox available_downloads_listbox;
    [GtkChild]
    private Gtk.Button install_rhel_button;
    [GtkChild]
    private Gtk.Image install_rhel_image;
    [GtkChild]
    private Boxes.WizardWebView rhel_web_view;
    [GtkChild]
    private Gtk.ListBox downloads_list;

    private AppWindow window;

    private Gtk.ListBox media_vbox;

    private Gtk.ListStore? media_urls_store;

    private Cancellable? rhel_cancellable;
    private Gtk.TreeRowReference? rhel_os_row_reference;
    private Osinfo.Os? rhel_os;

    public MediaManager media_manager;

    public string filename { get; set; }

    public bool download_required {
        get {
            string scheme = Uri.parse_scheme (uri);

            return (scheme != null && scheme in Downloader.supported_schemes);
        }
    }

    public Osinfo.Os? get_os_from_uri (string uri) {
        Osinfo.Os? os = null;

        media_urls_store.foreach ((store, path, iter) => {
            string? os_uri;
            media_urls_store.get (iter,
                                  OSDatabase.MediaURLsColumns.URL, out os_uri,
                                  OSDatabase.MediaURLsColumns.OS, out os);
            return os_uri == uri;
        });

        return os;
    }

    private SourcePage _page;
    public SourcePage page {
        get { return _page; }
        set {
            _page = value;

            if (rhel_cancellable != null) {
                rhel_cancellable.cancel ();
                rhel_cancellable = null;
            }

            visible_child_name = page_names[value];

            if (selected != null)
                selected.grab_focus ();
            switch (value) {
            case SourcePage.MAIN:
                add_media_entries.begin ();
                // FIXME: grab first element in the menu list
                main_vbox.grab_focus ();
                break;
            case SourcePage.RHEL_WEB_VIEW:
            case SourcePage.DOWNLOADS:
                break;
            case SourcePage.URL:
                url_entry.changed ();
                url_entry.grab_focus ();
                break;
            }
        }
    }

    construct {
        media_manager = MediaManager.get_instance ();
        main_vbox.grab_focus ();

        var num_visible = (Gdk.Screen.height () > 800)? 3 : 2;
        media_scrolled.setup (num_visible);
        media_vbox = media_scrolled.vbox;
        media_vbox.row_activated.connect((row) => {
            var entry = (row as WizardMediaEntry);
            on_media_selected (entry.media);

            selected = entry;
        });
        draw_as_css_box (url_entry_vbox);

        update_libvirt_sytem_entry_visibility.begin ();
        add_media_entries.begin ();

        rhel_web_view.view.decide_policy.connect (on_rhel_web_view_decide_policy);
    }

    public override void dispose () {
        if (rhel_cancellable != null) {
            rhel_cancellable.cancel ();
            rhel_cancellable = null;
        }

        base.dispose ();
    }

    public void setup_ui (AppWindow window) {
        assert (window != null);

        this.window = window;

        var os_db = media_manager.os_db;

        var available_downloads_model = new GLib.ListStore (typeof (Osinfo.Os));
        available_downloads_listbox.bind_model (available_downloads_model, create_downloadable_entry);
        available_downloads_listbox.row_activated.connect (on_downloadable_entry_clicked);

        downloads_list.bind_model (available_downloads_model, create_downloadable_entry);
        downloads_list.row_activated.connect (on_downloadable_entry_clicked);

        os_db.list_latest_downloadable_oses.begin ((db, result) => {
            try {
                var table = os_db.list_latest_downloadable_oses.end (result);

                foreach (var os in table.get_values ()) {
                    available_downloads_model.insert_sorted (os, (a, b) => {
                        var os1 = a as Osinfo.Os;
                        var os2 = b as Osinfo.Os;

                        if (Downloader.fetch_os_logo_url (os1) != null)
                            return -1;

                        if (Downloader.fetch_os_logo_url (os2) != null)
                            return 1;

                        return 0;
                    });
                }
            } catch (OSDatabaseError error) {
                debug ("Failed to populate the list of downloadable OSes: %s", error.message);
            }
        });

        os_db.get_all_media_urls_as_store.begin ((db, result) => {
            try {
                media_urls_store = os_db.get_all_media_urls_as_store.end (result);
                var completion = new Gtk.EntryCompletion ();
                completion.text_column = OSDatabase.MediaURLsColumns.URL;
                completion.model = media_urls_store;
                weak Gtk.CellRendererText cell = completion.get_cells ().nth_data (0) as Gtk.CellRendererText;
                cell.ellipsize = Pango.EllipsizeMode.MIDDLE;
                completion.set_match_func ((store, key, iter) => {
                    string url;

                    media_urls_store.get (iter, OSDatabase.MediaURLsColumns.URL, out url);

                    return url.contains (key);
                });
                url_entry.completion = completion;
            } catch (OSDatabaseError error) {
                debug ("Failed to get all known media URLs: %s", error.message);
            }
        });

        // We need a Shadowman logo and libosinfo mandates that we specify an
        // OsinfoOs to get a logo. However, we don't have an OsinfoOs to begin
        // with, and by the time we get one from the Red Hat developer portal
        // it will be too late.
        //
        // To work around this, we specify the ID of a RHEL release and use it
        // to get an OsinfoOs. Since all RHEL releases have the same Shadowman,
        // the exact version of the RHEL release doesn't matter.
        //
        // Ideally, distributions would be a first-class object in libosinfo, so
        // that we could query for RHEL instead of a specific version of it.
        var rhel_id = "http://redhat.com/rhel/7.4";

        os_db.get_os_by_id.begin (rhel_id, (obj, res) => {
            try {
                rhel_os = os_db.get_os_by_id.end (res);
            } catch (OSDatabaseError error) {
                warning ("Failed to find OS with ID '%s': %s", rhel_id, error.message);
                return;
            }

            Downloader.fetch_os_logo.begin (install_rhel_image, rhel_os, 64, (obj, res) => {
                Downloader.fetch_os_logo.end (res);
                var pixbuf = install_rhel_image.pixbuf;
                install_rhel_image.visible = pixbuf != null;
            });
        });
    }

    private Gtk.Widget create_downloadable_entry (Object item) {
        var os = item as Osinfo.Os;

        var entry = new WizardDownloadableEntry (os);
        entry.activated.connect ((media) => {
            this.uri = media.url;
        activated ();
        });

        return entry;
    }

    private void on_downloadable_entry_clicked (Gtk.ListBoxRow row) {
        var entry = (row as WizardDownloadableEntry);

        selected = entry;
        if (entry.single_media != null) {
           this.uri = entry.single_media.url;

           activated ();
        } else {
            entry.toggle();
        }
    }

    public void cleanup () {
        filename = null;
        install_media = null;
        libvirt_sys_import = false;
        selected = null;
        if(page != SourcePage.URL)
            uri = "";

        if (rhel_cancellable != null) {
            rhel_cancellable.cancel ();
            rhel_cancellable = null;
        }
    }

    [GtkCallback]
    private void on_enter_url_button_clicked () {
        page = SourcePage.URL;
    }

    [GtkCallback]
    private void on_url_entry_activated () {
        activated ();
    }

    [GtkCallback]
    private void on_url_back_button_clicked () {
        selected = null;
        page = SourcePage.MAIN;
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

        media_scrolled.show ();
    }

    private async void update_libvirt_sytem_entry_visibility () {
        try {
            libvirt_sys_importer = yield new LibvirtSystemImporter ();
        } catch (GLib.Error error) {
            debug ("%s", error.message);

            return;
        }
        libvirt_sys_import_label.label = libvirt_sys_importer.wizard_menu_label;
        libvirt_sys_import_button.show_all ();
    }

    [GtkCallback]
    private void on_select_file_button_clicked () {
        window.wizard_window.show_file_chooser ((uri) => {
            this.uri = uri;
            // clean install_media as this may be set already when going back in the wizard
            install_media = null;
            activated ();

            selected = select_file_button;
        });
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

    [GtkCallback]
    private void on_download_an_os_button_clicked () {
        page = SourcePage.DOWNLOADS;
    }

    [GtkCallback]
    private void on_install_rhel_button_clicked () {
        page = SourcePage.RHEL_WEB_VIEW;

        rhel_cancellable = new GLib.Cancellable ();
        rhel_cancellable.connect(() => {
            rhel_web_view.view.stop_loading ();
            rhel_web_view.view.load_uri ("about:blank");

            var data_manager = rhel_web_view.view.get_website_data_manager ();
            data_manager.clear.begin (WebKit.WebsiteDataTypes.COOKIES, 0, null);
        });

        var user_agent = get_user_agent ();
        var user_agent_escaped = GLib.Uri.escape_string (user_agent, null, false);
        var authentication_uri = "https://developers.redhat.com/download-manager/rest/featured/file/rhel" +
                                 "?tag=" + user_agent_escaped;

        debug ("RHEL ISO authentication URI: %s", authentication_uri);

        rhel_web_view.view.load_uri (authentication_uri);
    }

    private bool on_rhel_web_view_decide_policy (WebKit.WebView web_view,
                                                 WebKit.PolicyDecision decision,
                                                 WebKit.PolicyDecisionType decision_type) {
        if (decision_type != WebKit.PolicyDecisionType.NAVIGATION_ACTION)
            return false;

        var action = (decision as WebKit.NavigationPolicyDecision).get_navigation_action ();
        var request = action.get_request ();
        var request_uri = request.get_uri ();
        if (!request_uri.has_prefix ("https://developers.redhat.com/products/rhel"))
            return false;

        var soup_request_uri = new Soup.URI (request_uri);
        var query = soup_request_uri.get_query ();
        if (query == null)
            return false;

        var key_value_pairs = Soup.Form.decode (query);
        var download_uri = key_value_pairs.lookup ("tcDownloadURL");
        if (download_uri == null)
            return false;

        debug ("RHEL ISO download URI: %s", download_uri);

        if (rhel_os != null) {
            Gtk.TreeIter iter;
            Gtk.TreePath? path;
            bool iter_is_valid = false;

            if (rhel_os_row_reference == null) {
                media_urls_store.append (out iter);
                iter_is_valid = true;

                path = media_urls_store.get_path (iter);
                rhel_os_row_reference = new Gtk.TreeRowReference (media_urls_store, path);
            } else {
                path = rhel_os_row_reference.get_path ();
                iter_is_valid = media_urls_store.get_iter (out iter, path);
            }

            if (iter_is_valid) {
                media_urls_store.set (iter,
                                      OSDatabase.MediaURLsColumns.URL, download_uri,
                                      OSDatabase.MediaURLsColumns.OS, rhel_os);
            }
        }

        var soup_download_uri = new Soup.URI (download_uri);
        var download_path = soup_download_uri.get_path ();

        // Libsoup is supposed to ensure that the path is at least "/".
        return_val_if_fail (download_path != null, false);
        return_val_if_fail (download_path.length > 0, false);

        if (!download_path.has_suffix (".iso")) {
            download_path = "/rhel.iso";
        }

        filename = GLib.Path.get_basename (download_path);

        uri = download_uri;
        activated ();

        selected = install_rhel_button;

        decision.ignore ();
        return true;
    }
}
