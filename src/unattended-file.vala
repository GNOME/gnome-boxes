// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;

private interface Boxes.UnattendedFile : GLib.Object {
    public abstract string src_path { get; set; }
    public abstract string dest_name { get; set; }

    protected abstract UnattendedInstaller installer  { get; set; }

    public async void copy (Cancellable? cancellable) throws GLib.Error {
        var source_file = yield get_source_file (cancellable);

        debug ("Copying unattended file '%s' into disk drive/image '%s'", dest_name, installer.disk_file.get_path ());
        // FIXME: Perhaps we should use libarchive for this?
        string[] argv = { "mcopy", "-n", "-o", "-i", installer.disk_file.get_path (),
                                   source_file.get_path (),
                                   "::" + dest_name };
        yield exec (argv, cancellable);
        debug ("Copied unattended file '%s' into disk drive/image '%s'", dest_name, installer.disk_file.get_path ());
    }

    protected abstract async File get_source_file (Cancellable? cancellable)  throws GLib.Error;
}

private class Boxes.UnattendedRawFile : GLib.Object, Boxes.UnattendedFile {
    public string dest_name { get; set; }
    public string src_path { get; set; }

    protected UnattendedInstaller installer  { get; set; }

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

    protected UnattendedInstaller installer { get; set; }
    protected InstallScript script { get; set; }

    private File unattended_tmp;

    public UnattendedScriptFile (UnattendedInstaller installer, InstallScript script, string dest_name) {
       this.installer = installer;
       this.script = script;
       this.dest_name = dest_name;
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

        unattended_tmp = yield script.generate_output_async (installer.os, installer.config, output_dir, cancellable);

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

        dest_name = installer.username + "." + pixbuf_format.get_extensions ()[0];
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
