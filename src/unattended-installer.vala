// This file is part of GNOME Boxes. License: LGPLv2+

using GVirConfig;

public errordomain UnattendedInstallerError {
    SETUP_INCOMPLETE
}

private abstract class Boxes.UnattendedInstaller: InstallerMedia {
    public override bool need_user_input_for_vm_creation {
        get {
            return !live; // No setup required by live media (and unknown medias are not UnattendedInstaller instances)
        }
    }

    public virtual bool ready_for_express { get { return username != ""; } }

    public override bool ready_to_create {
        get {
            return !express_toggle.active || ready_for_express;
        }
    }

    public bool express_install {
        get { return express_toggle.active; }
    }

    public string username {
        get { return username_entry.text; }
    }

    public string password {
        owned get { return password_entry.text; }
    }

    public string hidden_password {
        owned get {
            if (password_entry.text.length > 0) {
                var str = "";
                for (var i = 0; i < password_entry.text_length; i++)
                    str += password_entry.get_invisible_char ().to_string ();

                return str;
            } else
                return _("no password");
        }
    }

    public DataStreamNewlineType newline_type;
    public File? disk_file;

    private string _extra_iso;
    protected string extra_iso {
        owned get { return lookup_extra_iso (_extra_iso); }
        set { _extra_iso = value; }
    }

    protected GLib.List<UnattendedFile> unattended_files;

    protected Gtk.Grid setup_grid;
    protected int setup_grid_n_rows;

    protected Gtk.Label setup_label;
    protected Gtk.HBox setup_hbox;
    protected Gtk.Switch express_toggle;
    protected Gtk.Entry username_entry;
    protected Gtk.Entry password_entry;

    protected string timezone;
    protected string lang;
    protected string hostname;

    protected AvatarFormat avatar_format;

    private static Regex username_regex;
    private static Regex password_regex;
    private static Regex timezone_regex;
    private static Regex lang_regex;
    private static Regex host_regex;
    private static Fdo.Accounts? accounts;

    static construct {
        try {
            username_regex = new Regex ("BOXES_USERNAME");
            password_regex = new Regex ("BOXES_PASSWORD");
            timezone_regex = new Regex ("BOXES_TZ");
            lang_regex = new Regex ("BOXES_LANG");
            host_regex = new Regex ("BOXES_HOSTNAME");
        } catch (RegexError error) {
            // This just can't fail
            assert_not_reached ();
        }
    }

    construct {
        /* We can't do this in the class constructor as the sync call can
           cause deadlocks, see bug #676679. */
        if (accounts == null) {
            try {
                accounts = Bus.get_proxy_sync (BusType.SYSTEM, "org.freedesktop.Accounts", "/org/freedesktop/Accounts");
            } catch (GLib.Error error) {
                warning ("Failed to connect to D-Bus service '%s': %s", "org.freedesktop.Accounts", error.message);
            }
        }
    }

    public UnattendedInstaller.from_media (InstallerMedia media,
                                           string         unattended_src_path,
                                           string         unattended_dest_name,
                                           AvatarFormat?  avatar_format = null) throws GLib.Error {
        os = media.os;
        os_media = media.os_media;
        label = media.label;
        device_file = media.device_file;
        from_image = media.from_image;
        mount_point = media.mount_point;
        resources = media.resources;

        newline_type = DataStreamNewlineType.LF;

        unattended_files = new GLib.List<UnattendedFile> ();
        add_unattended_file (new UnattendedTextFile (this, unattended_src_path, unattended_dest_name));

        var time = TimeVal ();
        var date = new DateTime.from_timeval_local (time);
        timezone = date.get_timezone_abbreviation ();

        var langs = Intl.get_language_names ();
        lang = langs[0];

        this.avatar_format = avatar_format;
        if (avatar_format == null)
            this.avatar_format = new AvatarFormat ();

        setup_ui ();
    }

    public override async void prepare_for_installation (string vm_name, Cancellable? cancellable) throws GLib.Error {
        if (!express_toggle.active) {
            debug ("Unattended installation disabled.");

            return;
        }
        this.hostname = vm_name.replace (" ", "-");

        try {
            yield create_disk_image (cancellable);

            foreach (var unattended_file in unattended_files)
                yield unattended_file.copy (cancellable);
        } catch (GLib.Error error) {
            clean_up ();
            // An error occurred when trying to setup unattended installation, but it's likely that a non-unattended
            // installation will work. When this happens, just disable unattended installs, and let the caller decide
            // if it wants to retry a non-automatic install or to just abort the box creation..
            express_toggle.active = false;

            throw error;
        } finally {
            unattended_files = null;
        }
    }

    public override void setup_domain_config (Domain domain) {
        base.setup_domain_config (domain);

        var disk = get_unattended_disk_config ();
        if (disk == null)
            return;

        domain.add_device (disk);
    }

    // Allows us to add an extra install media, for example with more windows drivers
    public void add_extra_iso (Domain domain) {
        if (extra_iso == null)
            return;

        add_cd_config (domain, DomainDiskType.FILE, extra_iso, "hdd", false);
    }

    public override void populate_setup_vbox (Gtk.VBox setup_vbox) {
        foreach (var child in setup_vbox.get_children ())
            setup_vbox.remove (child);

        setup_vbox.pack_start (setup_label, false, false);
        setup_vbox.pack_start (setup_hbox, false, false);
        setup_vbox.show_all ();
    }

    public override List<Pair> get_vm_properties () {
        var properties = base.get_vm_properties ();

        if (express_install) {
            properties.append (new Pair<string,string> (_("Username"), username));
            properties.append (new Pair<string,string> (_("Password"), hidden_password));
        }

        return properties;
    }

    public virtual string fill_unattended_data (string data) throws RegexError {
        var str = username_regex.replace (data, data.length, 0, username_entry.text);
        str = password_regex.replace (str, str.length, 0, password);
        str = timezone_regex.replace (str, str.length, 0, timezone);
        str = lang_regex.replace (str, str.length, 0, lang);
        str = host_regex.replace (str, str.length, 0, hostname);

        return str;
    }

    public string get_user_unattended (string? suffix = null) {
        var filename = hostname;
        if (suffix != null)
            filename += "-" + suffix;

        return get_user_pkgcache (filename);
    }

    protected virtual void setup_ui () {
        setup_label = new Gtk.Label (_("Choose express install to automatically preconfigure the box with optimal settings."));
        setup_label.wrap = true;
        setup_label.width_chars = 30;
        setup_label.halign = Gtk.Align.START;
        setup_hbox = new Gtk.HBox (false, 0);
        setup_hbox.valign = Gtk.Align.START;
        setup_hbox.margin = 24;

        setup_grid = new Gtk.Grid ();
        setup_hbox.pack_start (setup_grid, false, false);
        setup_grid.column_spacing = 0;
        setup_grid.column_homogeneous = false;
        setup_grid.row_spacing = 0;
        setup_grid.row_homogeneous = true;

        // First row
        // Translators: 'Express Install' means that the new box installation will be fully automated, the user
        // won't be asked anything while it's performed.
        var label = new Gtk.Label (_("Express Install"));
        label.margin_right = 10;
        label.margin_bottom = 15;
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.CENTER;
        setup_grid.attach (label, 0, 0, 2, 1);

        express_toggle = new Gtk.Switch ();
        express_toggle.active = !os_media.live;
        express_toggle.margin_bottom = 15;
        express_toggle.halign = Gtk.Align.START;
        express_toggle.valign = Gtk.Align.CENTER;
        express_toggle.notify["active"].connect (() => { notify_property ("ready-to-create"); });
        setup_grid.attach (express_toggle, 2, 0, 1, 1);
        setup_grid_n_rows++;

        // 2nd row (while user avatar spans over 2 rows)
        var avatar = new Gtk.Image.from_icon_name ("avatar-default", 0);
        avatar.pixel_size = 64;
        avatar.margin_right = 15;
        avatar.valign = Gtk.Align.CENTER;
        avatar.halign = Gtk.Align.CENTER;
        setup_grid.attach (avatar, 0, 1, 1, 2);
        avatar.show_all ();
        fetch_user_avatar.begin (avatar);

        label = new Gtk.Label (_("Username"));
        label.margin_right = 10;
        label.margin_bottom  = 10;
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.END;
        setup_grid.attach (label, 1, 1, 1, 1);
        username_entry = create_input_entry (Environment.get_user_name ());
        username_entry.margin_bottom  = 10;
        username_entry.halign = Gtk.Align.FILL;
        username_entry.valign = Gtk.Align.END;
        setup_grid.attach (username_entry, 2, 1, 1, 1);
        setup_grid_n_rows++;

        // 3rd row
        label = new Gtk.Label (_("Password"));
        label.margin_right = 10;
        label.halign = Gtk.Align.END;
        label.valign = Gtk.Align.START;
        setup_grid.attach (label, 1, 2, 1, 1);

        var notebook = new Gtk.Notebook ();
        notebook.show_tabs = false;
        notebook.show_border = false;
        notebook.halign = Gtk.Align.FILL;
        notebook.valign = Gtk.Align.START;
        var button = new Gtk.Button.with_mnemonic (_("_Add Password"));
        button.visible = true;
        notebook.append_page (button);
        password_entry = create_input_entry ("", false, false);
        notebook.append_page (password_entry);
        button.clicked.connect (() => {
            notebook.next_page ();
            password_entry.is_focus = true;
        });
        password_entry.focus_out_event.connect (() => {
            if (password_entry.text_length == 0)
                notebook.prev_page ();
            return false;
        });
        setup_grid.attach (notebook, 2, 2, 1, 1);
        setup_grid_n_rows++;

        foreach (var child in setup_grid.get_children ())
            if (child != express_toggle)
                express_toggle.bind_property ("active", child, "sensitive", BindingFlags.SYNC_CREATE);
    }

    protected virtual void clean_up () throws GLib.Error {
        if (disk_file != null) {
            delete_file (disk_file);

            disk_file = null;
        }
    }

    protected virtual DomainDisk? get_unattended_disk_config () {
        if (!express_toggle.active)
            return null;

        return_val_if_fail (disk_file != null, null);

        var disk = new DomainDisk ();
        disk.set_type (DomainDiskType.FILE);
        disk.set_guest_device_type (DomainDiskGuestDeviceType.DISK);
        disk.set_driver_name ("qemu");
        disk.set_driver_type ("raw");
        disk.set_source (disk_file.get_path ());
        disk.set_target_dev ("sdb");

        return disk;
    }

    protected void add_unattended_file (UnattendedFile file) {
        unattended_files.append (file);
    }

    protected Gtk.Entry create_input_entry (string text, bool mandatory = true, bool visibility = true) {
        var entry = new Gtk.Entry ();
        entry.visibility = visibility;
        entry.visible = true;
        entry.text = text;

        if (mandatory)
            entry.notify["text"].connect (() => {
                notify_property ("ready-to-create");
            });

        return entry;
    }

    private async void create_disk_image (Cancellable? cancellable) throws GLib.Error {
        var disk_path = get_user_unattended ("unattended.img");
        disk_file = File.new_for_path (disk_path);

        var template_path = get_unattended ("disk.img");
        var template_file = File.new_for_path (template_path);

        debug ("Creating disk image for unattended installation at '%s'..", disk_path);
        yield template_file.copy_async (disk_file, FileCopyFlags.OVERWRITE, Priority.DEFAULT, cancellable);
        debug ("Floppy image for unattended installation created at '%s'", disk_path);
    }

    private string? lookup_extra_iso (string name)
    {
        var path = get_user_pkgcache (name);

        if (FileUtils.test (path, FileTest.IS_REGULAR))
            return path;

        path = get_unattended (name);
        if (FileUtils.test (path, FileTest.IS_REGULAR))
            return path;

        return null;
    }

    private async void fetch_user_avatar (Gtk.Image avatar) {
        if (accounts == null)
            return;

        var username = Environment.get_user_name ();
        string avatar_path = "/var/lib/AccountsService/icons/" + username;

        try {
            var path = yield accounts.FindUserByName (Environment.get_user_name ());
            Fdo.AccountsUser user = yield Bus.get_proxy (BusType.SYSTEM, "org.freedesktop.Accounts", path);
            avatar_path = user.IconFile;
        } catch (GLib.IOError error) {
            warning ("Failed to retrieve information about user '%s': %s", username, error.message);
        }

        try {
            var pixbuf = new Gdk.Pixbuf.from_file_at_scale (avatar_path, 64, 64, true);
            avatar.pixbuf = pixbuf;
            add_unattended_file (new UnattendedAvatarFile (this, avatar_path, avatar_format));
        } catch (GLib.Error error) {
            debug ("Failed to load user avatar file '%s': %s", avatar_path, error.message);
        }
    }
}

private interface Boxes.UnattendedFile : GLib.Object {
    protected abstract string src_path { get; set; }
    protected abstract string dest_name { get; set; }

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
    protected string src_path { get; set; }
    protected string dest_name { get; set; }

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

private class Boxes.UnattendedTextFile : GLib.Object, Boxes.UnattendedFile {
    protected string src_path { get; set; }
    protected string dest_name { get; set; }

    protected UnattendedInstaller installer  { get; set; }

    private File unattended_tmp;

    public UnattendedTextFile (UnattendedInstaller installer, string src_path, string dest_name) {
       this.installer = installer;
       this.src_path = src_path;
       this.dest_name = dest_name;
    }

    ~UnattendedTextFile () {
        try {
            delete_file (unattended_tmp);
        } catch (GLib.Error e) {
            warning ("Error deleting %s: %s", unattended_tmp.get_path (), e.message);
        }
    }

    protected async File get_source_file (Cancellable? cancellable)  throws GLib.Error {
        var source = File.new_for_path (src_path);
        var destination_path = installer.get_user_unattended (dest_name);
        var destination = File.new_for_path (destination_path);

        debug ("Creating unattended file at '%s'..", destination.get_path ());
        var input_stream = yield source.read_async (Priority.DEFAULT, cancellable);
        var output_stream = yield destination.replace_async (null,
                                                             false,
                                                             FileCreateFlags.REPLACE_DESTINATION,
                                                             Priority.DEFAULT,
                                                             cancellable);
        var data_stream = new DataInputStream (input_stream);
        data_stream.newline_type = DataStreamNewlineType.ANY;
        string? str;
        while ((str = yield data_stream.read_line_async (Priority.DEFAULT, cancellable)) != null) {
            str = installer.fill_unattended_data (str);

            str += (installer.newline_type == DataStreamNewlineType.LF) ? "\n" : "\r\n";

            yield output_stream.write_async (str.data, Priority.DEFAULT, cancellable);
        }
        yield output_stream.close_async (Priority.DEFAULT, cancellable);
        debug ("Created unattended file at '%s'..", destination.get_path ());
        unattended_tmp = destination;

        return destination;
    }
}

private class Boxes.UnattendedAvatarFile : GLib.Object, Boxes.UnattendedFile {
    protected string src_path { get; set; }
    protected string dest_name { get; set; }

    protected UnattendedInstaller installer  { get; set; }

    private File unattended_tmp;

    private AvatarFormat dest_format;

    public UnattendedAvatarFile (UnattendedInstaller installer, string src_path, AvatarFormat dest_format) {
        this.installer = installer;
        this.src_path = src_path;

        this.dest_format = dest_format;
    }

    ~UnattendedAvatarFile () {
        try {
            delete_file (unattended_tmp);
        } catch (GLib.Error e) {
            warning ("Error deleting %s: %s", unattended_tmp.get_path (), e.message);
        }
    }

    protected async File get_source_file (Cancellable? cancellable)  throws GLib.Error {
        dest_name = installer.username + dest_format.extension;
        var destination_path = installer.get_user_unattended (dest_name);

        try {
            var pixbuf = new Gdk.Pixbuf.from_file_at_scale (src_path, dest_format.width, dest_format.height, true);

            if (!dest_format.alpha && pixbuf.get_has_alpha ())
                pixbuf = remove_alpha (pixbuf);

            debug ("Saving user avatar file at '%s'..", destination_path);
            pixbuf.save (destination_path, dest_format.type);
            debug ("Saved user avatar file at '%s'.", destination_path);
        } catch (GLib.Error error) {
            warning ("Failed to save user avatar: %s.", error.message);
        }

        unattended_tmp = File.new_for_path (destination_path);

        return unattended_tmp;
    }
}

private class AvatarFormat {
    public string type;
    public string extension;
    public bool alpha;
    public int width;
    public int height;

    public AvatarFormat (string type = "png",
                         string extension = "",
                         bool   alpha = true,
                         int    width = -1,
                         int    height = -1) {
        this.type = type;
        this.extension = extension;
        this.alpha = alpha;
        this.width = width;
        this.height = height;
    }
}
