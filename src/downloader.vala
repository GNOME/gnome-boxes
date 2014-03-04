// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.Download {
    public string uri;
    public File cached_file;
    public ActivityProgress progress;

    public Download (string uri, File cached_file, ActivityProgress progress) {
        this.uri = uri;
        this.cached_file = cached_file;
        this.progress = progress;
    }
}

private class Boxes.Downloader : GLib.Object {
    private static Downloader downloader;
    private Soup.Session session;

    private GLib.HashTable<string,Download> downloads;

    public signal void downloaded (Download download);
    public signal void download_failed (Download download, GLib.Error error);

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
        downloads = new GLib.HashTable <string,Download> (str_hash, str_equal);

        session = new Soup.Session ();
        session.add_feature_by_type (typeof (Soup.ProxyResolverDefault));
    }

    public async File download (File             remote_file,
                                string           cached_path,
                                ActivityProgress progress = new ActivityProgress ()) throws GLib.Error {
        var uri = remote_file.get_uri ();
        var download = downloads.get (uri);
        if (download != null)
            // Already being downloaded
            return yield await_download (download, cached_path, progress);

        var cached_file = File.new_for_path (cached_path);
        if (cached_file.query_exists ()) {
            debug ("'%s' already available locally at '%s'. Not downloading.", uri, cached_path);
            return cached_file;
        }

        debug ("Downloading '%s'...", uri);
        download = new Download (uri, cached_file, progress);
        downloads.set (uri, download);

        try {
            if (remote_file.has_uri_scheme ("http") || remote_file.has_uri_scheme ("https"))
                yield download_from_http (download);
            else
                yield copy_file (remote_file, cached_file); // FIXME: No progress report in this case.
        } catch (GLib.Error error) {
            download_failed (download, error);

            throw error;
        } finally {
            downloads.remove (uri);
        }

        debug ("Downloaded '%s' and its now locally available at '%s'.", uri, cached_path);
        downloaded (download);

        return cached_file;
    }

    private async void download_from_http (Download download) throws GLib.Error {
        var msg = new Soup.Message ("GET", download.uri);
        var address = msg.get_address ();
        var connectable = new NetworkAddress (address.name, (uint16) address.port);
        var network_monitor = NetworkMonitor.get_default ();
        if (!(yield network_monitor.can_reach_async (connectable)))
            throw new Boxes.Error.INVALID ("Failed to reach host '%s' on port '%d'", address.name, address.port);

        int64 total_num_bytes = 0;
        msg.got_headers.connect (() => {
            total_num_bytes =  msg.response_headers.get_content_length ();
        });

        int64 current_num_bytes = 0;
        msg.got_chunk.connect ((msg, chunk) => {
            if (total_num_bytes <= 0)
                return;

            current_num_bytes += chunk.length;
            download.progress.progress = (double) current_num_bytes / total_num_bytes;
        });

        session.queue_message (msg, (session, msg) => {
            download_from_http.callback ();
        });
        yield;
        if (msg.status_code != Soup.Status.OK)
            throw new Boxes.Error.INVALID (msg.reason_phrase);
        yield download.cached_file.replace_contents_async (msg.response_body.data, null, false, 0, null, null);
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

    private async File? await_download (Download         download,
                                        string           cached_path,
                                        ActivityProgress progress) throws GLib.Error {
        File downloaded_file = null;
        GLib.Error download_error = null;

        download.progress.bind_property ("progress", progress, "progress", BindingFlags.SYNC_CREATE);
        SourceFunc callback = await_download.callback;
        var downloaded_id = downloaded.connect ((downloader, downloaded) => {
            if (downloaded.uri != download.uri)
                return;

            downloaded_file = downloaded.cached_file;
            callback ();
        });
        var downloaded_failed_id = download_failed.connect ((downloader, failed_download, error) => {
            if (failed_download.uri != download.uri)
                return;

            download_error = error;
            callback ();
        });

        debug ("'%s' already being downloaded. Waiting for download to complete..", download.uri);
        yield; // Wait for it
        debug ("Finished waiting for '%s' to download.", download.uri);
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
