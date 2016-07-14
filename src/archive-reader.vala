// This file is part of GNOME Boxes. License: LGPLv2+

public class Boxes.ArchiveReader : GLib.Object {
    // This is the block size used by example code on the libarchive website
    private const int BLOCK_SIZE = 10240;

    public Archive.Read archive;

    private string filename;
    private Archive.Format? format;
    private GLib.List<Archive.Filter>? filters;

    public ArchiveReader (string                     filename,
                          Archive.Format?            format  = null,
                          GLib.List<Archive.Filter>? filters = null)
                          throws GLib.IOError {
        this.filename = filename;
        this.format = format;
        if (filters != null)
            this.filters = filters.copy ();

        open_archive ();
    }

    public GLib.List<string> get_file_list () throws GLib.IOError {
        var result = new GLib.List<string> ();
        unowned Archive.Entry iterator;
        while (get_next_header (archive, out iterator))
            result.append (iterator.pathname ());

        return result;
    }

    // convenience wrapper, don't use it for extracting more than one file for performance reasons!
    public void extract_file (string src,
                              string dest,
                              bool   override_if_necessary = false)
                              throws GLib.IOError {
        extract_files_recursive ({src}, {dest}, override_if_necessary);
    }

    public void reset () throws GLib.IOError {
        execute_libarchive_function (archive, archive.close);
        open_archive ();
    }

    private void extract_files_recursive (string[] src_list,
                                          string[] dest_list,
                                          bool     override_if_necessary = false,
                                          bool     follow_hardlinks      = true)
                                          throws GLib.IOError
                                          requires (src_list.length == dest_list.length) {
        if (src_list.length == 0)
            return;

        unowned Archive.Entry iterator;
        uint i = 0;
        string[] hardlink_src = {};
        string[] hardlink_dest = {};
        // FIXME: split out some things out of this ugly loop
        while (get_next_header (archive, out iterator) && (i < src_list.length)) {
            var dest = get_dest_file (src_list, dest_list, iterator.pathname ());

            if (dest == null) {
                // file is not to be extracted
                execute_libarchive_function (archive, archive.read_data_skip);

                continue;
            }

            if (iterator.hardlink () != null && iterator.size () == 0) {
                debug ("Following hardlink of '%s' to '%s'.", iterator.pathname (), iterator.hardlink ());
                hardlink_src += iterator.hardlink ();
                hardlink_dest += dest;
                i++;

                continue;
            }

            if (!override_if_necessary && FileUtils.test (dest, FileTest.EXISTS))
                throw new GLib.IOError.EXISTS ("Destination file '%s' already exists.", dest);

            // read data into file
            var fd = FileStream.open (dest, "w+");
            execute_libarchive_function (archive, () => { return archive.read_data_into_fd (fd.fileno ()); });

            debug ("Extracted file '%s' from archive '%s'.", dest, filename);
            i++;
        }

        if (src_list.length != i)
            throw new GLib.IOError.NOT_FOUND ("At least one specified file was not found in the archive.");

        reset ();

        if (hardlink_src.length > 0) {
            if (follow_hardlinks) {
                extract_files_recursive (hardlink_src, hardlink_dest, override_if_necessary, false);
            } else {
                var msg = "Maximum recursion depth exceeded. It is likely that a hardlink points to itself.";

                throw new GLib.IOError.WOULD_RECURSE (msg);
            }
        }
    }

    private string? get_dest_file (string[] src_list, string[] dest_list, string src) {
        for (uint j = 0; j < src_list.length; j++) {
            if (src_list[j] == src)
                return dest_list[j];
        }

        return null;
    }

    private void open_archive () throws GLib.IOError {
        archive = new Archive.Read ();

        if (format == null)
            execute_libarchive_function (archive, archive.support_format_all);
        else
            execute_libarchive_function (archive, () => { return archive.set_format (format); });

        if (filters == null) {
            execute_libarchive_function (archive, archive.support_filter_all);
        } else {
            foreach (var filter in filters)
                execute_libarchive_function (archive, () => { return archive.append_filter (filter); });
        }

        execute_libarchive_function (archive, () => { return archive.open_filename (filename, BLOCK_SIZE); });
    }
}
