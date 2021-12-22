// This file is part of GNOME Boxes. License: LGPLv2+

using GVirConfig;
using Govf;

private class Boxes.InstalledMedia : Boxes.InstallerMedia {
    public const string[] supported_extensions = { ".qcow2", ".qcow2.gz",
                                                   ".qcow", ".qcow.gz",
                                                   ".img", ".img.gz",
                                                   ".cow", ".cow.gz",
                                                   ".ova", ".ova.gz",
                                                   ".vdi", ".vdi.gz",
                                                   ".vmdk", ".vmdk.gz",
                                                   ".vpc", ".vpc.gz",
                                                   ".cloop", ".cloop.gz" };
    public const string[] supported_architectures = {
        "i686", "i586", "i486", "i386", "x86_64", "amd64"
    };

    public override bool need_user_input_for_vm_creation { get { return false; } }
    public override bool ready_to_create { get { return true; } }
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

    public InstalledMedia (string path, bool known_qcow2 = false) throws GLib.Error {
        var supported = false;

        if (known_qcow2 || path.has_prefix ("/dev/"))
            supported = true; // Let's assume it's device file in raw format
        else
            foreach (var extension in supported_extensions) {
                supported = path.down ().has_suffix (extension);
                if (supported)
                    break;
            }

        if (!supported)
            throw new IOError.NOT_SUPPORTED (_("Unsupported disk image format."));

        // FIXME with the proper implementation
        skip_import = path.down ().has_suffix (".qcow2");

        device_file = path;
        from_image = true;

        label_setup ();
    }

    public async InstalledMedia.guess_os (string path) throws GLib.Error {
        this (path);

        resources = OSDatabase.get_default_resources ();

        label_setup ();
    }

    // Also converts to native format (QCOW2)
    public async void copy (string destination_path) throws GLib.Error {
        var decompressed = yield decompress ();
        var extracted = yield extract_ovf ();

        string[] argv = { "qemu-img", "convert", "-O", "qcow2", device_file, destination_path };

        var converting = !device_file.has_suffix (".qcow2");

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

    public override GLib.List<Pair<string,string>> get_vm_properties () {
        var properties = new GLib.List<Pair<string,string>> ();

        properties.append (new Pair<string,string> (_("System"), label));

        return properties;
    }


    public override VMCreator get_vm_creator () {
        return new VMImporter (this);
    }

    private async bool extract_ovf () throws GLib.Error {
        if (!device_file.has_suffix (".ova"))
            return false;

        var ova_file = File.new_for_path (device_file);
        var ovf_package = new Govf.Package ();
        yield ovf_package.load_from_ova_file (device_file, null);

        var disks = ovf_package.get_disks ();
        var extracted_path = get_user_pkgcache (ova_file.get_basename () + ".vmkd");
        yield ovf_package.extract_disk (disks [0], extracted_path, null);

        debug ("Extracted '%s' from '%s'.", extracted_path, device_file);

        device_file = extracted_path;

        return true;
    }

    private async bool decompress () throws GLib.Error {
        if (!device_file.has_suffix (".gz"))
            return false;

        var compressed = File.new_for_path (device_file);
        var input_stream = yield compressed.read_async ();

        var decompressed_path = Path.get_basename (device_file).replace (".gz", "");
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
