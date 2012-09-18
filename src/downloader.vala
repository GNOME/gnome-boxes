// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.Downloader : GLib.Object {
    private static Downloader downloader;
    private Soup.SessionAsync session;

    private GLib.HashTable<string,File> downloads;

    public signal void downloaded (string uri, File cached_file);
    public signal void download_failed (string uri, File cached_file, GLib.Error error);

    public static Downloader get_instance () {
        if (downloader == null)
            downloader = new Downloader ();

        return downloader;
    }

    private static string fetch_os_logo_url (Osinfo.Os os) {
        if (os.logo != null)
            return os.logo;

        string logo_url = null;
        var derived = os.get_related (Osinfo.ProductRelationship.DERIVES_FROM);
        while (derived.get_length () > 0 && logo_url == null) {
            // FIXME: Does Osinfo allows deriving from multiple OSs?
            var parent = derived.get_nth (0) as Osinfo.Os;

            if (parent.logo != null)
                logo_url = parent.logo;
            else
                derived = parent.get_related (Osinfo.ProductRelationship.DERIVES_FROM);
        }

        return logo_url;
    }

    private Downloader () {
        downloads = new GLib.HashTable <string,File> (str_hash, str_equal);

        session = new Soup.SessionAsync ();
		session.add_feature_by_type (typeof (Soup.ProxyResolverDefault));
    }

    public async File download (File remote_file, string cached_path) throws GLib.Error {
        var uri = remote_file.get_uri ();

        if (downloads.contains (uri))
            // Already being downloaded
            return yield await_download (uri, cached_path);

        var cached_file = File.new_for_path (cached_path);
        if (cached_file.query_exists ()) {
            debug ("'%s' already available locally at '%s'. Not downloading.", uri, cached_path);
            return cached_file;
        }

        debug ("Downloading '%s'...", uri);
        downloads.set (uri, cached_file);

        try {
            var msg = new Soup.Message ("GET", uri);
            session.queue_message (msg, (session, msg) => {
                download.callback ();
            });
            yield;
            if (msg.status_code != Soup.KnownStatusCode.OK)
                throw new Boxes.Error.INVALID (msg.reason_phrase);
            yield cached_file.replace_contents_async (msg.response_body.data, null, false, 0, null, null);
        } catch (GLib.Error error) {
            download_failed (uri, cached_file, error);

            throw error;
        } finally {
            downloads.remove (uri);
        }

        debug ("Downloaded '%s' and its now locally available at '%s'.", uri, cached_path);
        downloaded (uri, cached_file);

        return cached_file;
    }

    public static async void fetch_os_logo (Gtk.Image image, Osinfo.Os os, int size) {
        var logo_url = fetch_os_logo_url (os);
        if (logo_url == null)
            return;

        debug ("%s has logo '%s'.", os.name, logo_url);

        var remote_file = File.new_for_uri (logo_url);
        var cached_path = get_logo_cache (remote_file.get_basename ());
        try {
            var cached_file = yield get_instance ().download (remote_file, cached_path);
            var pixbuf = new Gdk.Pixbuf.from_file_at_size (cached_file.get_path (), size, size);
            image.set_from_pixbuf (pixbuf);
        } catch (GLib.Error error) {
            warning ("Error loading logo file '%s': %s", logo_url, error.message);
        }
    }

    private async File? await_download (string uri, string cached_path) throws GLib.Error {
        File downloaded_file = null;
        GLib.Error download_error = null;

        SourceFunc callback = await_download.callback;
        var downloaded_id = downloaded.connect ((downloader, downloaded_uri, file) => {
            if (downloaded_uri != uri)
                return;

            downloaded_file = file;
            callback ();
        });
        var downloaded_failed_id = download_failed.connect ((downloader, downloaded_uri, file, error) => {
            if (downloaded_uri != uri)
                return;

            download_error = error;
            callback ();
        });

        debug ("'%s' already being downloaded. Waiting for download to complete..", uri);
        yield; // Wait for it
        debug ("Finished waiting for '%s' to download.", uri);
        disconnect (downloaded_id);
        disconnect (downloaded_failed_id);

        if (download_error != null)
            throw download_error;

        File cached_file;
        if (downloaded_file.get_path () != cached_path) {
            cached_file = File.new_for_path (cached_path);
            yield downloaded_file.copy_async (cached_file, FileCopyFlags.OVERWRITE);
        } else
            cached_file = downloaded_file;

        return cached_file;
    }
}
