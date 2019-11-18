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

    public DownloadChosenFunc download_chosen_func;

    [GtkChild]
    private Gtk.ListBox listbox;
    [GtkChild]
    private Gtk.ListBox recommended_listbox;

    private GLib.ListStore recommended_model;

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

        recommended_model = new GLib.ListStore (typeof (Osinfo.Media));
        recommended_listbox.bind_model (recommended_model, create_downloads_entry);
        populate_recommended_list.begin ();

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

    private async void populate_recommended_list () {
        foreach (var media in yield get_recommended_downloads ()) {
            recommended_model.append (media);
        }
    }

    private Gtk.Widget create_downloads_entry (Object item) {
        return new WizardDownloadableEntry (item as Osinfo.Media);
    }

    [GtkCallback]
    private void on_listbox_row_activated (Gtk.ListBoxRow row) {
        media_selected (row);
    }

    [GtkCallback]
    private void on_show_more_button_clicked () {
        search.show_all ();

        page = AssistantDownloadsPageView.SEARCH_RESULTS;
    }
}
