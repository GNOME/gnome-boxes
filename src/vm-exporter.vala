// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.VMExporter : GLib.Object {
    private LibvirtMachine machine;
    private string destination;

    public VMExporter (LibvirtMachine machine, string destination) {
        this.machine = machine;

    }

    public async void export () {
        var xml = machine.domain_config.to_xml ();

        print (xml);

        string? device_file = null;
        foreach (var device in machine.domain_config.get_devices ()) {
            if (device is GVirConfig.DomainDisk) {
                device_file = (device as GVirConfig.DomainDisk).get_source ();

                break;
            }
        }

        if (device_file != null) {

            print ("device_file %s\n", device_file);
            Archive.Write archive = new Archive.Write ();
            archive.add_filter_gzip ();
            archive.set_format_pax_restricted ();
            archive.open_filename (destination);

            GLib.File file = GLib.File.new_for_path (device_file);
            GLib.File parent_dir = GLib.File.new_for_path (".");
            try {
                GLib.FileInfo file_info = file.query_info (GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE);
                FileInputStream input_stream = file.read ();
                DataInputStream data_input_stream = new DataInputStream (input_stream);

                Archive.Entry entry = new Archive.Entry ();
                entry.set_pathname (parent_dir.get_relative_path (file));
                entry.set_size ((Archive.int64_t)file_info.get_size ());
                entry.set_filetype ((Archive.FileType) Posix.S_IFREG);
                entry.set_perm(0644);

                if (archive.write_header (entry) != Archive.Result.OK) {
                    critical ("Error writing '%s': %s (%d)", file.get_path (), archive.error_string (), archive.errno ());

                    return;
                }

                size_t bytes_read;
                uint8[] buffer = new uint8[64];
                while (data_input_stream.read_all (buffer, out bytes_read)) {
                    if (bytes_read <= 0) {
                        break;
                    }

                    archive.write_data_block (buffer, bytes_read);
                }
            } catch (GLib.Error e) {
                critical (e.message);
            }

            if (archive.close () != Archive.Result.OK) {
                error ("Error : %s (%d)", archive.error_string (), archive.errno ());
            }
        }
    }
}
