// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.FedoraInstaller: UnattendedInstaller {
    private bool mounted;

    private File source_dir;
    private File kernel_file;
    private File initrd_file;

    public FedoraInstaller.copy (InstallerMedia media) throws GLib.Error {
        var source_path = get_unattended_dir ("ks.cfg");

        base.copy (media, source_path, "ks.cfg");
    }

    protected override async void prepare_direct_boot (Cancellable? cancellable) throws GLib.Error {
        if (!express_toggle.active)
            return;

        if (os_media.kernel_path == null || os_media.initrd_path == null)
            return;

        yield mount_media (cancellable);

        yield extract_boot_files (cancellable);

        yield normal_clean_up (cancellable);
    }

    protected override void clean_up () throws GLib.Error {
        base.clean_up ();

        if (kernel_file != null) {
            debug ("Removing '%s'..", kernel_path);
            kernel_file.delete ();
            debug ("Removed '%s'.", kernel_path);
        }

        if (initrd_file != null) {
            debug ("Removing '%s'..", initrd_path);
            initrd_file.delete ();
            debug ("Removed '%s'.", initrd_path);
        }
    }

    private async void normal_clean_up (Cancellable? cancellable) throws GLib.Error {
        if (!mounted)
            return;

        debug ("Unmounting '%s'..", mount_point);
        string[] argv = { "fusermount", "-u", mount_point };
        yield exec (argv, cancellable);
        debug ("Unmounted '%s'.", mount_point);

        source_dir.delete ();
        debug ("Removed '%s'.", mount_point);
    }

    private async void mount_media (Cancellable? cancellable) throws GLib.Error {
        if (mount_point != null) {
            source_dir = File.new_for_path (mount_point);

            return;
        }

        mount_point = get_user_unattended_dir (os.short_id);
        var dir = File.new_for_path (mount_point);
        try {
            dir.make_directory (null);
        } catch (IOError.EXISTS error) {}
        source_dir = dir;

        debug ("Mounting '%s' on '%s'..", device_file, mount_point);
        string[] argv = { "fuseiso", device_file, mount_point };
        yield exec (argv, cancellable);
        debug ("'%s' now mounted on '%s'.", device_file, mount_point);

        mounted = true;
    }

    private async void extract_boot_files (Cancellable? cancellable) throws GLib.Error {
        kernel_path = Path.build_filename (mount_point, os_media.kernel_path);
        kernel_file = File.new_for_path (os_media.kernel_path);
        initrd_path = Path.build_filename (mount_point, os_media.initrd_path);
        initrd_file = File.new_for_path (os_media.initrd_path);

        if (!mounted)
            return;

        kernel_path = get_user_unattended_dir (os.short_id + "-kernel");
        kernel_file = yield copy_file (kernel_file, kernel_path, cancellable);
        initrd_path = get_user_unattended_dir (os.short_id + "-initrd");
        initrd_file = yield copy_file (initrd_file, initrd_path, cancellable);
    }

    private async File copy_file (File file, string dest_path, Cancellable? cancellable) throws GLib.Error {
        var dest_file = File.new_for_path (dest_path);

        try {
            yield file.copy_async (dest_file, 0, Priority.DEFAULT, cancellable);
        } catch (IOError.EXISTS error) {}

        return dest_file;
    }
}
