// This file is part of GNOME Boxes. License: LGPLv2+

// Helper class to extract files from an ISO image
private class Boxes.ISOExtractor: GLib.Object {
    private string device_file;

    public ISOExtractor (string iso_path) {
        this.device_file = iso_path;
    }

    public async void extract (string path, string output_path, Cancellable? cancellable) throws GLib.Error {
        debug ("Extracting '%s' from '%s' at path '%s'..", path, device_file, output_path);
        var reader = new ArchiveReader (device_file);
        reader.extract_file (path, output_path, true);
        debug ("Extracted '%s' from '%s' at path '%s'.", path, device_file, output_path);
    }
}
