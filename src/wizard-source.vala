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

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-downloadable-entry.ui")]
public class Boxes.WizardDownloadableEntry : Gtk.ListBoxRow {
    public Osinfo.Os? os;

    [GtkChild]
    private Gtk.Image media_image;
    [GtkChild]
    private Gtk.Label title_label;
    [GtkChild]
    private Gtk.Label details_label;

    public string title {
        get { return title_label.get_text (); }
        set { title_label.label = value; }
    }

    public string details {
        get { return details_label.get_text (); }
        set { details_label.label = value; }
    }
    public string url;

    public WizardDownloadableEntry (Osinfo.Media media) {
        this.from_os (media.os);

        setup_label (media);
        details = media.os.vendor;

        url = media.url;
    }

    public WizardDownloadableEntry.from_os (Osinfo.Os os) {
        Downloader.fetch_os_logo.begin (media_image, os, 64);

        this.os = os;
    }

    private void setup_label (Osinfo.Media media) {
        /* Libosinfo lacks some OS variant names, so we do some
           parsing here to compose a unique human-readable media
           identifier. */
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

            title = file.get_basename ().replace ("_", "");
        }

        var subvariant = "";
        if (media.url.contains ("netinst"))
            subvariant = "(netinst)";
        else if (media.url.contains ("minimal"))
            subvariant = "(minimal)";
        else if (media.url.contains ("dvd"))
            subvariant = "(DVD)";

        var is_live = media.live ? " (" + _("Live") + ")" : "";

        title = @"$variant $(media.architecture) $subvariant $is_live";

        /* Strip consequent whitespaces */
        title = title.replace ("  ", "");
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
    private Boxes.WizardScrolled downloads_scrolled;
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
    private Boxes.WizardWebView rhel_web_view;

    private AppWindow window;

    private Gtk.ListBox media_vbox;
    private Gtk.ListBox downloads_vbox;
    private Osinfo.Os rhel_os;
    private GLib.ListStore downloads_model;

    private Cancellable? rhel_cancellable;

    public MediaManager media_manager;

    public string filename { get; set; }

    private string[] recommended_downloads = {
        "http://ubuntu.com/ubuntu/16.04",
        "http://opensuse.org/opensuse/42.3",
        "http://fedoraproject.org/fedora/27",
    };

    public bool download_required {
        get {
            string scheme = Uri.parse_scheme (uri);

            return (scheme != null && scheme in Downloader.supported_schemes);
        }
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

        downloads_scrolled.setup (num_visible);
        downloads_vbox = downloads_scrolled.vbox;
        downloads_vbox.row_activated.connect (on_downloadable_entry_clicked);

        media_scrolled.bind_property ("visible", downloads_scrolled, "visible", BindingFlags.INVERT_BOOLEAN);

        update_libvirt_sytem_entry_visibility.begin ();
        add_media_entries.begin ();

        // We manually add the custom download entries. Custom download entries
        // are items which require special handling such as an authentication
        // page before we obtain a direct image URL.
        var os_db = media_manager.os_db;
        var rhel_id = "http://redhat.com/rhel/7.4";
        os_db.get_os_by_id.begin (rhel_id, (obj, res) => {
            try {
                rhel_os = os_db.get_os_by_id.end (res);
            } catch (OSDatabaseError error) {
                warning ("Failed to find OS with ID '%s': %s", rhel_id, error.message);
                return;
            }
        });

        downloads_model = new GLib.ListStore (typeof (Osinfo.Media));

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

        downloads_vbox.bind_model (downloads_model, create_downloadable_entry);

        populate_recommended_downloads ();
    }

    private void populate_recommended_downloads () {
        var os_db = media_manager.os_db;
        foreach (var os_id in recommended_downloads) {
            os_db.get_os_by_id.begin (os_id, (obj, res) => {
                try {
                    var os = os_db.get_os_by_id.end (res);

                    // TODO: Select the desktop/workstation variant.
                    var media = os.get_media_list ().get_nth (0) as Osinfo.Media;

                    downloads_model.append (media);
                } catch (OSDatabaseError error) {
                    warning ("Failed to find OS with ID '%s': %s", os_id, error.message);
                    return;
                }
            });
        }
    }

    private Gtk.Widget create_downloadable_entry (Object item) {
        var media = item as Osinfo.Media;

        var entry = new WizardDownloadableEntry (media);

        return entry;
    }

    private void on_downloadable_entry_clicked (Gtk.ListBoxRow row) {
        var entry = (row as WizardDownloadableEntry);

        selected = entry;
        this.uri = entry.url;

        activated ();
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
        window.wizard_window.show_downloads_page (media_manager.os_db, downloads_model, (entry) => {
            // Handle custom downloads
            if (entry.os.id == "http://redhat.com/rhel/7.4") {
                on_install_rhel_button_clicked ();

                return;
            }

            this.uri = entry.url;

            activated ();

            window.wizard_window.page = WizardWindowPage.MAIN;
        });
    }

    private void on_install_rhel_button_clicked () {
        window.wizard_window.page = WizardWindowPage.MAIN;
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

        window.wizard_window.logos_table.insert (download_uri, rhel_os);

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

        decision.ignore ();
        return true;
    }
}
