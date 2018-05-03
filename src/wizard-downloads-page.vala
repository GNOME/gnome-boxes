// This file is part of GNOME Boxes. License: LGPLv2+

public enum WizardDownloadsPageView {
    RECOMMENDED,
    SEARCH_RESULTS,
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-downloads-page.ui")]
public class Boxes.WizardDownloadsPage : Gtk.Stack {
    private OSDatabase os_db = new OSDatabase ();
    public DownloadsSearch search { private set; get; }

    public delegate void DownloadChosenFunc (WizardDownloadableEntry entry);
    public DownloadChosenFunc download_chosen_func;

    [GtkChild]
    private Gtk.ListBox listbox;
    [GtkChild]
    private Gtk.ListBox recommended_listbox;

    private GLib.ListStore recommended_model;
    private string[] recommended_downloads = {
        "http://redhat.com/rhel/7.4",
        "http://ubuntu.com/ubuntu/17.10",
        "http://opensuse.org/opensuse/42.3",
        "http://fedoraproject.org/fedora/27",
    };

    private WizardDownloadsPageView _page;
    public WizardDownloadsPageView page {
        get { return _page; }
        set {
            _page = value;

            switch (_page) {
                case WizardDownloadsPageView.SEARCH_RESULTS:
                    visible_child_name = "search-results";
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
        populate_recommended_list ();

        listbox.bind_model (search.model, create_downloads_entry);

        search.search_changed.connect (set_visible_view);
    }

    private void set_visible_view () {
        visible_child_name = search.text.length == 0 ? "recommended" : "search-results";
    }

    private async void populate_recommended_list () {
        foreach (var os_id in recommended_downloads) {
            try {
                var os = yield os_db.get_os_by_id (os_id);
                var media = os.get_media_list ().get_nth (0) as Osinfo.Media;

                recommended_model.append (media);
            } catch (OSDatabaseError error) {
                warning ("Failed to find OS with id: '%s': %s", os_id, error.message);
            }
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
