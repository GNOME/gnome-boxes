// This file is part of GNOME Boxes. License: LGPLv2+

using GVirConfig;

private class Boxes.InstalledMedia : Boxes.InstallerMedia {
    public override bool need_user_input_for_vm_creation { get { return false; } }
    public override bool ready_to_create { get { return true; } }
    public override bool live { get { return false; } }

    public string format { get { return device_file.has_suffix (".qcow2")? "qcow2" : "raw"; } }

    protected override string? architecture {
        owned get {
            // Many distributors provide arch name on the image file so lets try to use that if possible
            if (device_file.contains ("amd64") || device_file.contains ("x86_64"))
                return "x86_64";
            else {
                string[] arch_list = { "i686", "i586", "i486", "i386" };
                foreach (var arch in arch_list) {
                    if (device_file.contains (arch))
                        return arch;
                }

                debug ("Failed to guess architecture for media '%s'.", device_file);
                return null;
            }
        }
    }

    public InstalledMedia (string path) throws GLib.Error {
        if (!path.has_suffix (".qcow2") && !path.has_suffix (".img"))
            throw new Boxes.Error.INVALID (_("Only QEMU QCOW Image (v2) and raw formats supported."));

        device_file = path;
        from_image = true;

        resources = OSDatabase.get_default_resources ();
        label_setup ();
    }

    public async void convert_to_native_format (string destination_path) throws GLib.Error {
        string[] argv = { "qemu-img", "convert", "-O", "qcow2", device_file, destination_path };

        var converting = !device_file.has_suffix (".qcow2");

        debug ("Copying '%s' to '%s'%s.",
               device_file,
               destination_path,
               converting? " while converting it to 'qcow2' format" : "");
        yield exec (argv, null);
        debug ("Finished copying '%s' to '%s'", device_file, destination_path);
    }

    public override void setup_domain_config (Domain domain) {}

    public override GLib.List<Pair<string,string>> get_vm_properties () {
        var properties = new GLib.List<Pair<string,string>> ();

        properties.append (new Pair<string,string> (_("System"), label));

        return properties;
    }


    public override VMCreator get_vm_creator () {
        return new VMImporter (this);
    }
}
