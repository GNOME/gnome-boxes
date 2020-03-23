// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.Download {
    public string uri;
    public File remote_file;
    public File cached_file;
    public ActivityProgress progress;

    public Download (File remote_file, File cached_file, ActivityProgress progress) {
        this.remote_file = remote_file;
        this.uri = remote_file.get_uri ();
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

    public static string[] supported_schemes = {
        "http",
        "https",
    };

    public static Downloader get_instance () {
        if (downloader == null)
            downloader = new Downloader ();

        return downloader;
    }

    public static string fetch_os_logo_url (Osinfo.Os os) {
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
        if (Environment.get_variable ("SOUP_DEBUG") != null)
            session.add_feature (new Soup.Logger (Soup.LoggerLogLevel.HEADERS, -1));

        // As some websites redirect based on UA, lets force wget user-agent so the
        // website assumes it's a CLI tool downloading the file.
        session.user_agent = "Wget/1.0";
    }

    /**
     * Downloads the given file.
     *
     * @param remote_file The remote file to download.
     * @param cached_paths Array of possible cache locations. If not found, the file will be saved
     *                     to the location specified by the first element.
     * @param progress The ActivityProgress object to report progress to.
     * @param cancellable The Cancellable object for cancellation.
     *
     * @return A file handle to the (now) local file.
     */
    public async File download (File             remote_file,
                                string[]         cached_paths,
                                ActivityProgress progress = new ActivityProgress (),
                                Cancellable?     cancellable = null) throws GLib.Error {
        var uri = remote_file.get_uri ();
        var download = downloads.get (uri);
        var cached_path = cached_paths[0];

        if (download != null)
            // Already being downloaded
            return yield await_download (download, cached_path, progress);

        var cached_file = get_cached_file (remote_file, cached_paths);
        if (cached_file != null)
            return cached_file;

        var tmp_path = cached_path + "~";
        var tmp_file = GLib.File.new_for_path (tmp_path);
        debug ("Downloading '%s'...", uri);
        download = new Download (remote_file, tmp_file, progress);
        downloads.set (uri, download);

        try {
            if (remote_file.get_uri_scheme () in supported_schemes)
                yield download_from_http (download, cancellable);
            else
                yield download_from_filesystem (download, cancellable);
        } catch (GLib.Error error) {
            download_failed (download, error);

            throw error;
        } finally {
            downloads.remove (uri);
        }

        cached_file = GLib.File.new_for_path (cached_path);
        tmp_file.move (cached_file, FileCopyFlags.NONE, cancellable);
        download.cached_file = cached_file;

        debug ("Downloaded '%s' and it's now locally available at '%s'.", uri, cached_path);
        downloaded (download);

        return cached_file;
    }

    private async void download_from_http (Download download, Cancellable? cancellable = null) throws GLib.Error {
        var msg = new Soup.Message ("GET", download.uri);
        msg.response_body.set_accumulate (false);
        var address = msg.get_address ();
        var connectable = new NetworkAddress (address.name, (uint16) address.port);
        var network_monitor = NetworkMonitor.get_default ();
        if (!(yield network_monitor.can_reach_async (connectable)))
            throw new Boxes.Error.INVALID ("Failed to reach host '%s' on port '%d'", address.name, address.port);
        GLib.Error? err = null;
        ulong cancelled_id = 0;
        if (cancellable != null)
            cancelled_id = cancellable.connect (() => {
                err = new GLib.IOError.CANCELLED ("Cancelled by cancellable.");
                session.cancel_message (msg, Soup.Status.CANCELLED);
            });

        int64 total_num_bytes = 0;
        msg.got_headers.connect (() => {
            total_num_bytes =  msg.response_headers.get_content_length ();
        });

        var cached_file_stream = yield download.cached_file.replace_async (null,
                                                                           false,
                                                                           FileCreateFlags.REPLACE_DESTINATION);

        int64 current_num_bytes = 0;
        // FIXME: Reduce lambda nesting by splitting out downloading to Download class
        msg.got_chunk.connect ((msg, chunk) => {
            if (session.would_redirect (msg))
                return;

            current_num_bytes += chunk.length;
            try {
                // Write synchronously as we have no control over order of async
                // calls and we'll end up writing bytes out in wrong order. Besides
                // we are writing small chunks so it wouldn't really block the UI.
                cached_file_stream.write (chunk.data);
                if (total_num_bytes > 0)
                    // Don't report progress if there is no way to determine it
                    download.progress.progress = (double) current_num_bytes / total_num_bytes;
            } catch (GLib.Error e) {
                err = e;
                session.cancel_message (msg, Soup.Status.CANCELLED);
            }
        });

        session.queue_message (msg, (session, msg) => {
            download_from_http.callback ();
        });

        yield;

        if (cancelled_id != 0)
            cancellable.disconnect (cancelled_id);

        yield cached_file_stream.close_async (Priority.DEFAULT, cancellable);

        if (msg.status_code != Soup.Status.OK) {
            download.cached_file.delete ();
            if (err == null)
                err = new GLib.Error (Soup.http_error_quark (), (int)msg.status_code, msg.reason_phrase);

            throw err;
        }
    }

    public static async void fetch_os_logo (Gtk.Image image, Osinfo.Os os, int size) {
        var logo_url = fetch_os_logo_url (os);
        if (logo_url == null)
            return;

        debug ("%s has logo '%s'.", os.name, logo_url);

        var remote_file = File.new_for_uri (logo_url);
        var system_cached_path = get_system_logo_cache (remote_file.get_basename ());
        var cached_path = get_logo_cache (remote_file.get_basename ());

        string[] cached_paths = { cached_path };
        if (system_cached_path != null)
            cached_paths += system_cached_path;

        try {
            var cached_file = yield get_instance ().download (remote_file, cached_paths);
            var pixbuf = new Gdk.Pixbuf.from_file_at_size (cached_file.get_path (), size, size);
            image.set_from_pixbuf (pixbuf);
        } catch (GLib.Error error) {
            warning ("Error loading logo file '%s': %s", logo_url, error.message);
        }
    }

    public static async string fetch_media (string           uri,
                                            string?          filename = null,
                                            ActivityProgress progress = new ActivityProgress (),
                                            Cancellable?     cancellable = null) throws GLib.Error {
        var file = File.new_for_uri (uri);
        string? basename = null;

        if (filename == null) {
            basename = file.get_basename ();
        } else {
            basename = filename;
        }

        return_val_if_fail (basename != null && basename != "" && basename != "/", null);

        var downloader = Downloader.get_instance ();
        var cache = Path.build_filename (GLib.Environment.get_user_special_dir (GLib.UserDirectory.DOWNLOAD),
                                         basename);

        progress.progress = 0;
        debug ("Downloading media from '%s' to '%s'.", uri, cache);
        yield downloader.download (file, {cache}, progress, cancellable);
        progress.progress = 1;

        return cache;
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

    private async void download_from_filesystem (Download     download,
                                                 Cancellable? cancellable = null) throws GLib.Error {
        var src_file = download.remote_file;
        var dest_file = download.cached_file;

        try {
            debug ("Copying '%s' to '%s'..", src_file.get_path (), dest_file.get_path ());
            yield src_file.copy_async (dest_file,
                                       FileCopyFlags.OVERWRITE,
                                       Priority.DEFAULT,
                                       cancellable,
                                       (current, total) => {
                download.progress.progress = (double) current / total;
            });
            debug ("Copied '%s' to '%s'.", src_file.get_path (), dest_file.get_path ());
        } catch (IOError.EXISTS error) {}
    }

    private File? get_cached_file (File remote_file, string[] cached_paths) {
        foreach (var path in cached_paths) {
            var cached_file = File.new_for_path (path);
            if (cached_file.query_exists ()) {
                debug ("'%s' already available locally at '%s'. Not downloading.", remote_file.get_uri (), path);
                return cached_file;
            }
        }

        return null;
    }
}
