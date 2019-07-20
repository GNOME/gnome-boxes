// This file is part of GNOME Boxes. License: LGPLv2+

// Helper class to extract files from an installation tree location
private class Boxes.TreeExtractor: Boxes.Extractor {
    public TreeExtractor (string tree_url) {
        this.source_path = tree_url;
    }

    public async void extract (string file_path, string output_path, Cancellable? cancellable) throws GLib.Error {
        debug ("Extracting '%s' from '%s' at path '%s'..", file_path, source_path, output_path);
        var downloader = Downloader.get_instance ();
        var location = source_path + "/" + file_path;
        var remote_file = File.new_for_uri (location);
        var cached_path = get_cache (remote_file.get_basename ());
		string[] cached_paths = { cached_path };
		// TODO: Check if a file with similar name exists
        var cached_file = yield downloader.download (remote_file, cached_paths);

        debug ("Extracted '%s' from '%s' at path '%s'.", file_path, source_path, output_path);
 	}

}
