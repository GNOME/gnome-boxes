// This file is part of GNOME Boxes. License: LGPLv2+

// Helper class to extract files from an ISO image
private class Boxes.ISOExtractor: GLib.Object {
    private string device_file;
    private string mount_point;
    private bool mounted;

    public ISOExtractor (string iso_path) {
        this.device_file = iso_path;
    }

    ~ISOExtractor () {
        if (!mounted)
            return;

        debug ("Unmounting '%s'..", mount_point);
        string[] argv = { "fusermount", "-u", mount_point };
        exec.begin (argv, null);
        debug ("Unmounted '%s'.", mount_point);
    }

    public async void mount_media (Cancellable? cancellable) throws GLib.Error {
        if (mounted)
            return;

        string iso_name = File.new_for_path (device_file).get_basename ();

        string temp_name = get_user_pkgcache (iso_name + "-XXXXXX");
        string? mount_point = GLib.DirUtils.mkdtemp (temp_name);
        if (mount_point == null)
            throw (GLib.IOError) new GLib.Error (G_IO_ERROR, g_io_error_from_errno (errno), "Failed to create temporary mountpoint %s", temp_name);
        this.mount_point = mount_point;

        debug ("Mounting '%s' on '%s'..", device_file, mount_point);
        // the -p option tells fuseiso to rmdir the mountpoint on unmount
        string[] argv = { "fuseiso", "-p", device_file, mount_point };
        yield exec (argv, cancellable);
        debug ("'%s' now mounted on '%s'.", device_file, mount_point);

        mounted = true;
    }

    public async GLib.FileEnumerator enumerate_children (string rel_path, Cancellable? cancellable) throws GLib.Error
                                                         requires (mounted) {

        string abs_src_path = Path.build_filename (mount_point, rel_path);
        File dir = File.new_for_path (abs_src_path);

        return yield dir.enumerate_children_async (FileAttribute.STANDARD_NAME, 0, GLib.Priority.DEFAULT, cancellable);
    }

    public string get_absolute_path (string relative_path) throws GLib.Error
                                     requires (mounted) {
        return Path.build_filename (mount_point, relative_path);
    }
}
