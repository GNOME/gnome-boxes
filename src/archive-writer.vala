// This file is part of GNOME Boxes. License: LGPLv2+

// A non-threadsafe wrapper for libarchives write archive
public class Boxes.ArchiveWriter : GLib.Object {
    public Archive.Write archive;

    private GLib.List<Archive.Filter>? filters;
    private Archive.Format format;

    public ArchiveWriter (string                     filename,
                          Archive.Format             format,
                          GLib.List<Archive.Filter>? filters = null)
                          throws GLib.IOError {
        archive = new Archive.Write ();
        this.format  = format;
        this.filters = filters.copy ();

        prepare_archive ();
        execute_libarchive_function (archive, () => { return archive.open_filename (filename); });
    }

    public ArchiveWriter.from_fd (int fd,
                                  Archive.Format             format,
                                  GLib.List<Archive.Filter>? filters = null)
                                  throws GLib.IOError {
        archive = new Archive.Write ();
        this.format  = format;
        this.filters = filters.copy ();

        prepare_archive ();
        execute_libarchive_function (archive, () => { return archive.open_fd (fd); });
    }

    public ArchiveWriter.from_archive_reader (ArchiveReader archive_reader,
                                              string        filename,
                                              bool          import_contents = true)
                                              throws GLib.IOError {
        unowned Archive.Entry iterator;
        archive = new Archive.Write ();
        if (!get_next_header (archive_reader.archive, out iterator)) {
            var msg = "Error creating write archive for archive '%s'. It is probably empty.";
            throw new GLib.IOError.FAILED (msg, filename);
        }

        format = archive_reader.archive.format ();
        copy_filters_from_read_archive (archive_reader.archive);
        prepare_archive ();
        execute_libarchive_function (archive, () => { return archive.open_filename (filename); });

        archive_reader.reset ();

        if (import_contents)
            import_read_archive (archive_reader);
    }

    // if omit_hardlinked_files is true a file body will be omitted if it's on the list independently from it having a
    // hardlink pointing to it or not. If it is set to false a file body with a hardlink on the omittion list will
    // result in the file NOT being omitted.
    public void import_read_archive (ArchiveReader archive_reader,
                                     string[]?     omit_files = null,
                                     bool          omit_hardlinked_files = false)
                                     throws GLib.IOError {
        unowned Archive.Entry iterator;
        while (get_next_header (archive_reader.archive, out iterator)) {
            var omit = false;
            foreach (var file in omit_files) {
                if (file == iterator.pathname ()) {
                    omit = true;

                    break;
                }
            }

            if (omit) {
                if (omit_hardlinked_files || iterator.nlink () == 1 || iterator.hardlink () != null)
                    // File is a hardlink jost pointing somewhere or there's no hardlink to this file
                    // (or !omit_hardlinked_files)
                    continue;
                else
                    warning ("File '%s' cannot be omitted since a hardlink points to it.", iterator.pathname ());
            }

            var len = iterator.size ();
            execute_libarchive_function (archive, () => { return archive.write_header (iterator); });
            if (len > 0) {
                var buf = new uint8[len];
#if VALA_0_42
                insert_data (buf, archive_reader.archive.read_data (buf));
#else
                insert_data (buf, archive_reader.archive.read_data (buf, (size_t) len));
#endif
            }
        }

        archive_reader.reset ();
    }

    // convenience wrapper
    public void insert_files (string[] src_list,
                              string[] dest_list)
                              throws GLib.IOError
                              requires (src_list.length == dest_list.length) {
        for (uint i = 0; i < src_list.length; i++)
            insert_file (src_list[i], dest_list[i]);
    }

    // while dest is the destination relative to archive root
    public void insert_file (string src, string dest) throws GLib.IOError {
        if (!FileUtils.test (src, FileTest.EXISTS))
            throw new GLib.IOError.NOT_FOUND ("Source file '%s' cannot be injected. File not found.", src);

        if (FileUtils.test (src, FileTest.IS_SYMLINK))
            throw new GLib.IOError.NOT_SUPPORTED ("Inserting symlinks is currently not supported.");

        var entry = get_entry_for_file (src, dest);
        var len = entry.size ();
        var buf = new uint8[len];

        // get file info, read data into memory
        var filestream = GLib.FileStream.open (src, "r");
        filestream.read ((uint8[]) buf);
        execute_libarchive_function (archive, () => { return archive.write_header(entry); });
        insert_data (buf, len);
    }

    private void prepare_archive () throws GLib.IOError {
        execute_libarchive_function (archive, () => { return archive.set_format (format); });

        if (filters != null) {
            foreach (var filter in filters)
                execute_libarchive_function (archive, () => { return archive.add_filter (filter); });
        }
    }

    private void copy_filters_from_read_archive (Archive.Read read_archive) {
        filters = new GLib.List<Archive.Filter> ();
        for (var i = read_archive.filter_count () - 1; i > 0; i--)
            filters.append (read_archive.filter_code (i - 1));
    }

    private void insert_data (uint8[] data, int64 len) throws GLib.IOError {
#if VALA_0_42
        if (archive.write_data (data) != len)
#else
        if (archive.write_data (data, (size_t) data.length) != len)
#endif
            throw new GLib.IOError.FAILED ("Failed writing data to archive. Message: '%s'.",
                                           archive.error_string ());
    }

    private Archive.Entry get_entry_for_file (string filename, string dest_name) {
        Posix.Stat st;
        var result = new Archive.Entry ();

        Posix.stat (filename, out st);

        result.copy_stat (st);
        result.set_pathname (dest_name);

        return result;
    }
}
