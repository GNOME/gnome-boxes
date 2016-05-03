// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.LibvirtVMCloner : Boxes.LibvirtVMImporter {
    public LibvirtVMCloner (InstalledMedia source_media) {
        base (source_media);
    }

    public LibvirtVMCloner.for_cloning_completion (LibvirtMachine machine) {
        base.for_import_completion (machine);
    }

    protected override async void post_import_setup (LibvirtMachine machine) {
        try {
            var image_path = machine.storage_volume.get_path ();
            var argv = new string[] { "virt-sysprep", "-a", image_path };
            string std_output, std_error;

            yield exec (argv, null, out std_output, out std_error);

            if (std_error != "")
                debug ("Error output from virt-sysprep command: %s", std_error);
            debug ("Standard output from virt-sysprep command: %s", std_output);
        } catch (GLib.Error error) {
            // We don't want hard dep on libguestfs-tools so it's OK if virt-sysprep command fails
            debug ("Failed to run virt-sysprep: %s. You're on your own.", error.message);
        }

        yield base.post_import_setup (machine);
    }
}
