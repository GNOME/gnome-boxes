// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GUdev;

private class Boxes.InstallerMedia : Object {
    public Os? os;
    public Osinfo.Resources? resources;
    public Media? os_media;
    public string label;
    public string device_file;
    public string mount_point;
    public bool from_image;

    public bool live { get { return os_media == null || os_media.live; } }

    public InstallerMedia.from_iso_info (string            path,
                                         string            label,
                                         Os                os,
                                         Media?            media,
                                         Osinfo.Resources? resources) {
        this.device_file = path;
        this.label = label;
        this.os = os;
        this.os_media = media;
        this.resources = resources;
        from_image = true;

        if (media != null && media.live)
            this.label = _("%s (Live)").printf (label);
    }

    public static async InstallerMedia create_for_path (string       path,
                                                        MediaManager media_manager,
                                                        Cancellable? cancellable) throws GLib.Error {
        var media = new InstallerMedia ();

        yield media.setup_for_path (path, media_manager, cancellable);

        return media;
    }

    private async void setup_for_path (string       path,
                                       MediaManager media_manager,
                                       Cancellable? cancellable) throws GLib.Error {
        var device = yield get_device_from_path (path, media_manager.client, cancellable);

        if (device != null)
            get_media_info_from_device (device, media_manager.os_db);
        else {
            from_image = true;
            os = yield media_manager.os_db.guess_os_from_install_media (device_file, out os_media, cancellable);
        }

        if (os != null)
            label = os.get_name ();
            if (os_media != null && os_media.live)
                // Translators: We are appending " (Live)" suffix to name of OS media to indication that it's live.
                //              http://en.wikipedia.org/wiki/Live_CD
                label = _("%s (Live)").printf (label);

        if (label == null)
            label = Path.get_basename (device_file);

        // FIXME: these values could be made editable somehow
        var architecture = (os_media != null) ? os_media.architecture : "i686";
        resources = media_manager.os_db.get_resources_for_os (os, architecture);
    }

    private async GUdev.Device? get_device_from_path (string path, Client client, Cancellable? cancellable) {
        try {
            var mount_dir = File.new_for_commandline_arg (path);
            var mount = yield mount_dir.find_enclosing_mount_async (Priority.DEFAULT, cancellable);
            var root_dir = mount.get_root ();
            if (root_dir.get_path () == mount_dir.get_path ()) {
                var volume = mount.get_volume ();
                device_file = volume.get_identifier (VOLUME_IDENTIFIER_KIND_UNIX_DEVICE);
                mount_point = path;
            } else
                // Assume direct path to device node/image
                device_file = path;
        } catch (GLib.Error error) {
            // Assume direct path to device node/image
            device_file = path;
        }

        return client.query_by_device_file (device_file);
    }

    private void get_media_info_from_device (GUdev.Device device, OSDatabase os_db) throws OSDatabaseError {
        if (!device.get_property_as_boolean ("OSINFO_BOOTABLE"))
            throw new OSDatabaseError.NON_BOOTABLE ("Media %s is not bootable.", device_file);

        label = device.get_property ("ID_FS_LABEL");

        var os_id = device.get_property ("OSINFO_INSTALLER") ?? device.get_property ("OSINFO_LIVE");

        if (os_id != null) {
            os = os_db.get_os_by_id (os_id);

            var media_id = device.get_property ("OSINFO_MEDIA");
            if (media_id != null)
                os_media = os_db.get_media_by_id (os, media_id);
        }
    }
}
