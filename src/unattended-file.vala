// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;

private interface Boxes.UnattendedFile : GLib.Object {
    public abstract string src_path { get; set; }
    public abstract string dest_name { get; set; }

    protected string disk_file {
        owned get {
            return installer.disk_file.get_path ();
        }
    }
    protected abstract UnattendedInstaller installer { get; set; }

    public async virtual void copy (Cancellable? cancellable) throws GLib.Error {
        var source_file = yield get_source_file (cancellable);
        yield default_copy(disk_file, source_file.get_path (), dest_name);
    }

    protected static async void default_copy (string       disk_file,
                                              string       source_file,
                                              string       dest_name,
                                              Cancellable? cancellable = null)
                                              throws GLib.Error {
        debug ("Copying unattended file '%s' into disk drive/image '%s'", dest_name, disk_file);

        if (is_libarchive_compatible (disk_file)) {
            yield App.app.async_launcher.launch(() => {
                copy_with_libarchive (disk_file, source_file, dest_name);
            });
        } else
            yield copy_with_mcopy (disk_file, source_file, dest_name, cancellable);

        debug ("Copied unattended file '%s' into disk drive/image '%s'", dest_name, disk_file);
    }

    protected abstract async File get_source_file (Cancellable? cancellable)  throws GLib.Error;

    private static void copy_with_libarchive (string disk_file, string source_file, string dest_name) throws GLib.Error {
        var reader = new ArchiveReader (disk_file);
        // write into file~ since we can't write into the file we read from
        var writer = new ArchiveWriter.from_archive_reader (reader, disk_file + "~", false);
        // override the destination file if necessary
        writer.import_read_archive (reader, {dest_name});
        writer.insert_file (source_file, dest_name);

        // close files for moving
        reader = null;
        writer = null;

        var src = GLib.File.new_for_path (disk_file + "~");
        var dst = GLib.File.new_for_path (disk_file);
        // and copy the new file to overwrite the old one
        src.move (dst, FileCopyFlags.OVERWRITE);
    }

    private static async void copy_with_mcopy (string       disk_file,
                                               string       source_file,
                                               string       dest_name,
                                               Cancellable? cancellable = null)
                                               throws GLib.Error {
        string[] argv = {"mcopy",
                             "-n",
                             "-o",
                             "-i",
                                 disk_file,
                             source_file,
                             "::" + dest_name };
        yield exec (argv, cancellable);
    }

    private static bool is_libarchive_compatible (string filename) {
        // FIXME: We need better way to determine libarchive compatibility cause mcopy is used
        //        if this function returns false and mcopy can only handle MS-DOS images while
        //        libarchive can handle other types of disk images.
        //
        //        Just in case you get the idea to compare the content_type to
        //        "application/x-raw-disk-image", that's what we were doing but then it failed
        //        on systems with slighly older shared-mime-info where the content_type is
        //        detected as 'application-octetstream'.
        return !filename.has_suffix (".img") && !filename.has_suffix (".IMG");
    }
}

private class Boxes.UnattendedRawFile : GLib.Object, Boxes.UnattendedFile {
    public string dest_name { get; set; }
    public string src_path { get; set; }

    protected UnattendedInstaller installer { get; set; }

    public UnattendedRawFile (UnattendedInstaller installer, string src_path, string dest_name) {
        this.installer = installer;
        this.src_path = src_path;
        this.dest_name = dest_name;
    }

    protected async File get_source_file (Cancellable? cancellable)  throws GLib.Error {
        return File.new_for_path (src_path);
    }
}

private class Boxes.UnattendedScriptFile : GLib.Object, Boxes.UnattendedFile {
    public string dest_name { get; set; }
    public string src_path { get; set; }
    public InstallScriptInjectionMethod injection_method { get; set; }

    protected UnattendedInstaller installer { get; set; }
    protected InstallScript script { get; set; }

    private File unattended_tmp;

    public UnattendedScriptFile (UnattendedInstaller installer,
                                 InstallScript       script,
                                 string              dest_name)
                                 throws GLib.Error {
        this.installer = installer;
        this.script = script;
        this.dest_name = dest_name;

        var injection_methods = script.get_injection_methods ();
        if (InstallScriptInjectionMethod.DISK in injection_methods)
            injection_method = InstallScriptInjectionMethod.DISK;
        else if (InstallScriptInjectionMethod.FLOPPY in injection_methods)
            injection_method = InstallScriptInjectionMethod.FLOPPY;
        else if (InstallScriptInjectionMethod.INITRD in injection_methods)
            injection_method = InstallScriptInjectionMethod.INITRD;
        else
            throw new GLib.IOError.NOT_SUPPORTED ("No supported injection method available.");
    }

    public async void copy (Cancellable? cancellable) throws GLib.Error {
        var source_file = yield get_source_file (cancellable);
        if (injection_method == InstallScriptInjectionMethod.INITRD) {
            initrd_append (installer.initrd_file.get_path (), source_file.get_path (), dest_name);
        } else
            yield Boxes.UnattendedFile.default_copy(disk_file, source_file.get_path (), dest_name);
    }

    private static void initrd_append (string disk_file, string source_file, string dest_name) throws GLib.Error {
        debug ("Appending unattended file '%s' to initrd '%s'", dest_name, disk_file);
        var gzip_filter = new GLib.List<Archive.Filter> ();
        gzip_filter.append (Archive.Filter.GZIP);
        var file = FileStream.open (disk_file, "a");
        if (file == null)
            throw GLib.IOError.from_errno (errno);
        var writer = new ArchiveWriter.from_fd (file.fileno (), Archive.Format.CPIO_SVR4_NOCRC, gzip_filter);
        writer.insert_file (source_file, dest_name);
        debug ("Appended unattended file '%s' to initrd '%s'", dest_name, disk_file);
    }

    ~UnattendedScriptFile () {
        if (unattended_tmp == null)
            return;

        try {
            delete_file (unattended_tmp);
        } catch (GLib.Error e) {
            warning ("Error deleting %s: %s", unattended_tmp.get_path (), e.message);
        }
    }

    protected async File get_source_file (Cancellable? cancellable)  throws GLib.Error {
        installer.configure_install_script (script);
        var output_dir = File.new_for_path (get_user_pkgcache ());

        unattended_tmp = yield script.generate_output_for_media_async (installer.os_media,
                                                                       installer.config,
                                                                       output_dir,
                                                                       cancellable);

        return unattended_tmp;
    }
}

private class Boxes.UnattendedAvatarFile : GLib.Object, Boxes.UnattendedFile {
    public string dest_name { get; set; }
    public string src_path { get; set; }

    protected UnattendedInstaller installer  { get; set; }

    private File unattended_tmp;

    private AvatarFormat? avatar_format;
    private Gdk.PixbufFormat pixbuf_format;

    public UnattendedAvatarFile (UnattendedInstaller installer, string src_path, AvatarFormat? avatar_format)
                                 throws Boxes.Error {
        this.installer = installer;
        this.src_path = src_path;

        this.avatar_format = avatar_format;

        foreach (var format in Gdk.Pixbuf.get_formats ()) {
            if (avatar_format != null) {
                foreach (var mime_type in avatar_format.mime_types) {
                    if (mime_type in format.get_mime_types ()) {
                        pixbuf_format = format;

                        break;
                    }
                }
            } else if (format.get_name () == "png")
                pixbuf_format = format; // Fallback to PNG if supported

            if (pixbuf_format != null)
                break;
        }

        if (pixbuf_format == null)
            throw new Boxes.Error.INVALID ("Failed to find suitable format to save user avatar file in.");

        dest_name = installer.setup_box.username + "." + pixbuf_format.get_extensions ()[0];
    }

    ~UnattendedAvatarFile () {
        if (unattended_tmp == null)
            return;

        try {
            delete_file (unattended_tmp);
        } catch (GLib.Error e) {
            warning ("Error deleting %s: %s", unattended_tmp.get_path (), e.message);
        }
    }

    protected async File get_source_file (Cancellable? cancellable) throws GLib.Error {
        var destination_path = installer.get_user_unattended (dest_name);

        try {
            var width = (avatar_format != null)? avatar_format.width : -1;
            var height = (avatar_format != null)? avatar_format.height : -1;
            var pixbuf = new Gdk.Pixbuf.from_file_at_scale (src_path, width, height, true);

            if (avatar_format != null && !avatar_format.alpha && pixbuf.get_has_alpha ())
                pixbuf = remove_alpha (pixbuf);

            debug ("Saving user avatar file at '%s'..", destination_path);
            pixbuf.save (destination_path, pixbuf_format.get_name ());
            debug ("Saved user avatar file at '%s'.", destination_path);
        } catch (GLib.Error error) {
            warning ("Failed to save user avatar: %s.", error.message);
        }

        unattended_tmp = File.new_for_path (destination_path);

        return unattended_tmp;
    }
}
