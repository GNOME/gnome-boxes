// This file is part of GNOME Boxes. License: LGPLv2+

public enum WizardDownloadsPageView {
    RECOMMENDED,
    SEARCH_RESULTS,
    NO_RESULTS,
}

public delegate void Boxes.DownloadChosenFunc (Boxes.WizardDownloadableEntry entry);

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-downloads-page.ui")]
public class Boxes.WizardDownloadsPage : Gtk.Stack {
    private OSDatabase os_db = new OSDatabase ();
    public DownloadsSearch search { private set; get; }

    public DownloadChosenFunc download_chosen_func;

    [GtkChild]
    private Gtk.ListBox listbox;
    [GtkChild]
    private Gtk.ListBox recommended_listbox;

    private GLib.ListStore recommended_model;

    private WizardDownloadsPageView _page;
    public WizardDownloadsPageView page {
        get { return _page; }
        set {
            _page = value;

            switch (_page) {
                case WizardDownloadsPageView.SEARCH_RESULTS:
                    visible_child_name = "search-results";
                    break;
                case WizardDownloadsPageView.NO_RESULTS:
                    visible_child_name = "no-results";
                    break;
                case WizardDownloadsPageView.RECOMMENDED:
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
            page = WizardDownloadsPageView.RECOMMENDED;
        } else if (search.model.get_n_items () == 0) {
            page = WizardDownloadsPageView.NO_RESULTS;
        } else {
            page = WizardDownloadsPageView.SEARCH_RESULTS;
        }
    }

    private async void populate_recommended_list () {
        foreach (var media in yield get_recommended_downloads ()) {
            recommended_model.append (media);
        }
    }

    private Gtk.Widget create_downloads_entry (Object item) {
        var media = item as Osinfo.Media;

        return new WizardDownloadableEntry (media);
    }

    [GtkCallback]
    private void on_listbox_row_activated (Gtk.ListBoxRow row) {
        var entry = row as WizardDownloadableEntry;

        download_chosen_func (entry);
    }

    [GtkCallback]
    private void on_show_more_button_clicked () {
        search.show_all ();

        page = WizardDownloadsPageView.SEARCH_RESULTS;
    }
}
