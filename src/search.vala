// This file is part of GNOME Boxes. License: LGPLv2+

public class Boxes.DownloadsSearch : GLib.Object {
    private OSDatabase os_db;

    public GLib.ListStore model = new GLib.ListStore (typeof (Osinfo.Media));

    private GLib.List<Osinfo.Media> media_list;

    public signal void search_changed ();

    private string _text;
    public string text {
        set {
            _text = value;

            model.remove_all ();

            if (text.length > 0) {
                var query = canonicalize_for_search (text);
                foreach (var media in media_list) {
                    var name = canonicalize_for_search ((media.os as Osinfo.Product).name);
                    if (query in name)
                        model.append (media);
                }
            }

            search_changed ();
        }
        get {
            return _text;
        }
    }

    construct {
        os_db = new OSDatabase ();
        os_db.load.begin ();

        media_list = new GLib.List<Osinfo.Media> ();
        os_db.list_downloadable_oses.begin ((db, result) => {
            try {
                media_list = os_db.list_downloadable_oses.end (result);
            } catch (OSDatabaseError error) {
                debug ("Failed to populate the list of downloadable OSes: %s", error.message);
            }
        });
    }

    public void show_all () {
        foreach (var media in media_list) {
            model.append (media);
        }
    }
}
