// This file is part of GNOME Boxes. License: LGPLv2+

public enum AssistantDownloadsPageView {
    RECOMMENDED,
    SEARCH_RESULTS,
    NO_RESULTS,
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/downloads-page.ui")]
public class Boxes.AssistantDownloadsPage : Gtk.Stack {
    private OSDatabase os_db = new OSDatabase ();
    public DownloadsSearch search { private set; get; }

    [GtkChild]
    public unowned Gtk.ScrolledWindow scrolled_window;
    [GtkChild]
    private unowned Gtk.ListBox listbox;
    [GtkChild]
    private unowned Gtk.Stack stack;
    [GtkChild]
    private unowned Gtk.ListBox recommended_listbox;

    public Gtk.SearchEntry search_entry = new Gtk.SearchEntry ();
    private GLib.ListStore recommended_model;
    private Gtk.Button show_more_button;

    public signal void media_selected (Gtk.ListBoxRow row);

    private AssistantDownloadsPageView _page;
    public AssistantDownloadsPageView page {
        get { return _page; }
        set {
            _page = value;

            switch (_page) {
                case AssistantDownloadsPageView.SEARCH_RESULTS:
                    visible_child_name = "search-results";
                    break;
                case AssistantDownloadsPageView.NO_RESULTS:
                    visible_child_name = "no-results";
                    break;
                case AssistantDownloadsPageView.RECOMMENDED:
                default:
                    visible_child_name = "recommended";
                    break;
            }
        }
    }

    construct {
        os_db.load.begin ();

        search = new DownloadsSearch ();

        // TODO: move this into a UI file
        search_entry.search_changed.connect (on_search_changed);
        search_entry.width_chars = 50;
        search_entry.can_focus = true;
        search_entry.placeholder_text = _("Search for an OS or enter a download link…");
        search_entry.visible = true;

        recommended_model = new GLib.ListStore (typeof (Osinfo.Media));
        recommended_listbox.bind_model (recommended_model, create_downloads_entry);

        show_more_button = new Gtk.Button () {
            visible = true,
            image = new Gtk.Image () {
                visible = true,
                icon_name = "view-more-symbolic"
            }
        };
        show_more_button.clicked.connect (on_show_more_button_clicked);
        show_more_button.get_style_context ().add_class ("flat");
        recommended_listbox.add (show_more_button);

        listbox.bind_model (search.model, create_downloads_entry);

        search.search_changed.connect (set_visible_view);
    }

    private void set_visible_view () {
        if (search.text.length == 0) {
            page = AssistantDownloadsPageView.RECOMMENDED;
        } else if (search.model.get_n_items () == 0) {
            page = AssistantDownloadsPageView.NO_RESULTS;
        } else {
            page = AssistantDownloadsPageView.SEARCH_RESULTS;
        }
    }

    public async void populate_recommended_list () {
        if (recommended_model.get_n_items () != 0)
            return;

        var os_list = yield fetch_recommended_downloads_from_net ();
        if (os_list == null)
            os_list = yield get_recommended_downloads ();

        foreach (var media in os_list) {
            if (media != null) {
                recommended_model.append (media);
            }
        }

        if (recommended_model.get_n_items () > 0)
            stack.set_visible_child (recommended_listbox);
    }

    private Gtk.Widget create_downloads_entry (Object item) {
        return new AssistantDownloadableEntry.from_osinfo (item as Osinfo.Media);
    }

    [GtkCallback]
    private void on_listbox_row_activated (Gtk.ListBoxRow row) {
        media_selected (row);
    }

    private void on_show_more_button_clicked () {
        search.show_all ();

        page = AssistantDownloadsPageView.SEARCH_RESULTS;

        show_more_button.get_parent ().destroy ();
    }

    private void on_search_changed () {
        var text = search_entry.get_text ();

        if (text == null)
            return;

        search.text = text;
    }

    [GtkCallback]
    private bool on_key_pressed (Gtk.Widget widget, Gdk.EventKey event) {
        if (!search_entry.has_focus)
            search_entry.grab_focus ();

        return search_entry.key_press_event (event);
    }
}
