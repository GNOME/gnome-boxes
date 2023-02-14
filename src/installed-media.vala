// This file is part of GNOME Boxes. License: LGPLv2+

using GVirConfig;
using Govf;

private class Boxes.InstalledMedia : Boxes.InstallerMedia {
    public const string[] supported_architectures = {
        "i686", "i586", "i486", "i386", "x86_64", "amd64"
    };

    public override bool need_user_input_for_vm_creation { get { return false; } }
    public override bool live { get { return false; } }
    private bool is_gnome;

    protected override string? architecture {
        owned get {
            // Many distributors provide arch name on the image file so lets try to use that if possible
            if (device_file.contains ("amd64") || device_file.contains ("x86_64") || is_gnome)
                return "x86_64";
            else {
                foreach (var arch in supported_architectures) {
                    if (device_file.contains (arch))
                        return arch;
                }

                debug ("Failed to guess architecture for media '%s'.", device_file);
                return null;
            }
        }
    }

    public InstalledMedia (string path, bool skip_import = false) {
        this.skip_import = skip_import;

        if (skip_import)
            debug ("'%s' doesn't need to be imported", path);

        resources = OSDatabase.get_default_resources ();
        device_file = path;
        from_image = true;

        label_setup ();
    }

    public async InstalledMedia.for_path (string path, bool skip_import = false) {
        this (path, skip_import);
    }

    // Also converts to native format (QCOW2)
    public async void copy (string destination_path) throws GLib.Error {
        var decompressed = yield decompress ();
        var extracted = yield extract_ovf ();

        string[] argv = { "qemu-img", "convert", "-O", "qcow2", device_file, destination_path };

        var converting = !skip_import;

        debug ("Copying '%s' to '%s'%s.",
               device_file,
               destination_path,
               converting? " while converting it to 'qcow2' format" : "");
        yield exec (argv, null);
        debug ("Finished copying '%s' to '%s'", device_file, destination_path);

        if (decompressed || extracted) {
            // We decompressed into a temporary location
            var file = File.new_for_path (device_file);
            delete_file (file);
        }
    }

    public override void setup_domain_config (Domain domain) {
        add_cd_config (domain, from_image? DomainDiskType.FILE : DomainDiskType.BLOCK, null, "hdc", false);
    }

    public override VMCreator get_vm_creator () {
        return new VMImporter (this);
    }

    private async bool extract_ovf () throws GLib.Error {
        var media_manager = MediaManager.get_default ();
        if (!media_manager.media_matches_content_type (device_file, {"application/ovf"}))
            return false;

        var ova_file = File.new_for_path (device_file);
        var ovf_package = new Govf.Package ();
        yield ovf_package.load_from_ova_file (device_file, null);

        var disks = ovf_package.get_disks ();
        var extracted_path = get_user_pkgcache (ova_file.get_basename () + ".vmdk");
        yield ovf_package.extract_disk (disks [0], extracted_path, null);

        debug ("Extracted '%s' from '%s'.", extracted_path, device_file);

        device_file = extracted_path;

        return true;
    }

    private async bool decompress () throws GLib.Error {
        var media_manager = MediaManager.get_default ();
        if (!media_manager.path_is_compressed (device_file))
            return false;

        var compressed = File.new_for_path (device_file);
        var input_stream = yield compressed.read_async ();

        var decompressed_path = Path.get_basename (device_file).concat (".boxes");
        decompressed_path = get_user_pkgcache (decompressed_path);
        var decompressed = File.new_for_path (decompressed_path);
        GLib.OutputStream output_stream = yield decompressed.replace_async (null,
                                                                            false,
                                                                            FileCreateFlags.REPLACE_DESTINATION);
        var decompressor = new ZlibDecompressor (ZlibCompressorFormat.GZIP);
        output_stream = new ConverterOutputStream (output_stream, decompressor);

        debug ("Decompressing '%s'..", device_file);
        var buffer = new uint8[1048576];
        while (true) {
            var length = yield input_stream.read_async (buffer);
            if (length <= 0)
                break;

            ssize_t written = 0, i = 0;
            do {
                written = output_stream.write (buffer[i:length]);
                i += written;
            } while (i < length);
        }
        debug ("Decompressed '%s'.", device_file);

        device_file = decompressed_path;

        return true;
    }
}
