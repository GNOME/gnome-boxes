// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/rhel-download-dialog.ui")]
private class Boxes.RHELDownloadDialog : Gtk.Dialog {
    [GtkChild]
    private unowned Gtk.ProgressBar progress_bar;
    [GtkChild]
    private unowned WebKit.WebView web_view;

    private uint hide_progress_bar_id;
    private const uint progress_bar_id_timeout = 500;  // 500ms

    private bool is_rhel8 = false;

    private GLib.Cancellable cancellable = new GLib.Cancellable ();

    private AssistantDownloadableEntry entry;

    construct {
        var context = web_view.get_context ();
        var language_names = GLib.Intl.get_language_names ();
        context.set_preferred_languages (language_names);

        cancellable.connect (() => {
            web_view.stop_loading ();
            web_view.load_uri ("about:blank");

            var data_manager = web_view.get_website_data_manager ();
            data_manager.clear.begin (WebKit.WebsiteDataTypes.COOKIES, 0, null);
        });
    }

    public RHELDownloadDialog (AssistantDownloadableEntry entry) {
        set_transient_for (App.app.main_window);
        this.entry = entry;

        var user_agent = GLib.Uri.escape_string (get_user_agent (), null, false);
        var authentication_uri = "https://developers.redhat.com/download-manager/rest/featured/file/rhel" +
                                 "?tag=" + user_agent;

        var os = entry.os;
        is_rhel8 = os.id.has_prefix ("http://redhat.com/rhel/8");

        web_view.load_uri (authentication_uri);
    }

    [GtkCallback]
    private bool on_decide_policy (WebKit.WebView web_view,
                                   WebKit.PolicyDecision decision,
                                   WebKit.PolicyDecisionType decision_type) {
        if (decision_type != WebKit.PolicyDecisionType.NAVIGATION_ACTION)
            return false;

        var navigation_policy_decision = decision as WebKit.NavigationPolicyDecision;
        var action = navigation_policy_decision.get_navigation_action ();
        var request = action.get_request ();
        var request_uri = request.get_uri ();

        if (!request_uri.has_prefix ("https://developers.redhat.com/products/rhel") &&
            !request_uri.has_prefix ("https://access.cdn.redhat.com"))
            return false;

        Uri? uri = null;
        try {
            uri = Uri.parse (request_uri, UriFlags.NONE);
        } catch (UriError error) {
            return false;
        }

        var query = uri.get_query ();
        if (query == null)
            return false;

        var key_value_pairs = Soup.Form.decode (query);

        var download_uri = is_rhel8 ? request_uri : key_value_pairs.lookup ("tcDownloadURL");
        if (download_uri == null)
            return false;

        debug ("RHEL ISO download URI: %s", download_uri);

        entry.url = download_uri;
        DownloadsHub.get_default ().add_item (entry);

        decision.ignore ();
        this.close ();

        return true;
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

    public override void close () {
        cancellable.cancel ();

        base.close ();
        destroy ();
    }
}
