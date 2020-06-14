// This file is part of GNOME Boxes. License: LGPLv2+

using Tracker;

private class Boxes.TrackerISOQuery {
    private const string ISO_QUERY = "SELECT nie:isStoredAs(?iso)   nie:title(?iso)\n" +
                                     "       osinfo:id(?iso) osinfo:mediaId(?iso) osinfo:language(?iso)\n" +
                                     "FROM tracker:Software " +
                                     "{ ?iso nfo:isBootable true }";

    private Sparql.Cursor cursor;

    public async TrackerISOQuery (Sparql.Connection connection) throws GLib.Error {
        var iso_query = ISO_QUERY;
        debug ("Tracker SPARQL query: %s", iso_query);

        this.cursor = yield connection.query_async (iso_query);
    }

    public async bool fetch_next_iso_data (out string   path,
                                           out string   title,
                                           out string   os_id,
                                           out string   media_id,
                                           out string[] lang_list) throws GLib.Error {
        path = title = os_id = media_id = null;
        lang_list = null;

        if (!(yield cursor.next_async ()))
            return false;

        var file = File.new_for_uri (cursor.get_string (0));
        path = file.get_path ();
        if (path == null) {
            // FIXME: Support non-local files as well
            return yield fetch_next_iso_data (out path,
                                              out title,
                                              out os_id,
                                              out media_id,
                                              out lang_list);
        }

        title = cursor.get_string (1);
        os_id = cursor.get_string (2);
        media_id = cursor.get_string (3);
        var languages = cursor.get_string (4);

        lang_list = (languages != null)? languages.split (",") : new string[]{};

        return true;
    }
}
