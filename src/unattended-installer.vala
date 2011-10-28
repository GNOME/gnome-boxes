// This file is part of GNOME Boxes. License: LGPLv2+

public errordomain UnattendedInstallerError {
    COMMAND_FAILED
}

private abstract class Boxes.UnattendedInstaller: InstallerMedia {
    public string kernel_path;
    public string initrd_path;

    public string floppy_path;

    protected string unattended_src_path;
    protected string unattended_dest_name;

    private bool created_floppy;

    public UnattendedInstaller.copy (InstallerMedia media,
                                     string         unattended_src_path,
                                     string         unattended_dest_name) throws GLib.Error {
        os = media.os;
        os_media = media.os_media;
        label = media.label;
        device_file = media.device_file;
        from_image = media.from_image;

        floppy_path = get_pkgcache (os.short_id + "-unattended.img");
        this.unattended_src_path = unattended_src_path;
        this.unattended_dest_name = unattended_dest_name;
    }

    public async void setup (Cancellable? cancellable) throws GLib.Error {
        try {
            if (yield unattended_floppy_exists (cancellable))
                debug ("Found previously created unattended floppy image for '%s', re-using..", os.short_id);
            else {
                yield create_floppy_image (cancellable);
                yield copy_unattended_file (cancellable);
            }

            yield prepare_direct_boot (cancellable);
        } catch (GLib.Error error) {
            clean_up ();

            throw error;
        }
    }

    protected virtual void clean_up () throws GLib.Error {
        if (!created_floppy)
            return;

        var floppy_file = File.new_for_path (floppy_path);

        floppy_file.delete ();

        debug ("Removed '%s'.", floppy_path);
    }

    protected virtual async void prepare_direct_boot (Cancellable? cancellable) throws GLib.Error {}

    protected async void exec (string[] argv, Cancellable? cancellable) throws GLib.Error {
        SourceFunc continuation = exec.callback;
        GLib.Error error = null;
        var context = MainContext.get_thread_default ();

        g_io_scheduler_push_job ((job) => {
            try {
                exec_sync (argv);
            } catch (GLib.Error err) {
                error = err;
            }

            var source = new IdleSource ();
            source.set_callback (() => {
                continuation ();

                return false;
            });
            source.attach (context);

            return false;
        });

        yield;

        if (error != null)
            throw error;
    }

    private async void create_floppy_image (Cancellable? cancellable) throws GLib.Error {
        var floppy_file = File.new_for_path (floppy_path);
        var template_path = get_unattended_dir ("floppy.img");
        var template_file = File.new_for_path (template_path);

        debug ("Creating floppy image for unattended installation at '%s'..", floppy_path);
        yield template_file.copy_async (floppy_file, 0, Priority.DEFAULT, cancellable);
        debug ("Floppy image for unattended installation created at '%s'", floppy_path);

        created_floppy = true;
    }

    private async void copy_unattended_file (Cancellable? cancellable) throws GLib.Error {
        debug ("Putting unattended file: %s", unattended_dest_name);
        // FIXME: Perhaps we should use libarchive for this?
        string[] argv = { "mcopy", "-i", floppy_path,
                                   unattended_src_path,
                                   "::" + unattended_dest_name };
        yield exec (argv, cancellable);
        debug ("Put unattended file: %s", unattended_dest_name);
    }

    private async bool unattended_floppy_exists (Cancellable? cancellable) {
        var file = File.new_for_path (floppy_path);

        try {
            yield file.read_async (Priority.DEFAULT, cancellable);
        } catch (IOError.NOT_FOUND not_found_error) {
            return false;
        } catch (GLib.Error error) {}

        return true;
    }

    private void exec_sync (string[] argv) throws GLib.Error {
        int exit_status = -1;

        Process.spawn_sync (null,
                            argv,
                            null,
                            SpawnFlags.SEARCH_PATH,
                            null,
                            null,
                            null,
                            out exit_status);
        if (exit_status != 0)
            throw new UnattendedInstallerError.COMMAND_FAILED ("Failed to execute: %s", string.joinv (" ", argv));
    }
}
