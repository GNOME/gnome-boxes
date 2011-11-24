// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GUdev;

private class Boxes.InstallerMedia : Object {
    public Os os;
    public Media os_media;
    public string label;
    public string device_file;
    public string mount_point;
    public bool from_image;

    public static async InstallerMedia instantiate (string       path,
                                                    OSDatabase   os_db,
                                                    Client       client,
                                                    Cancellable? cancellable) throws GLib.Error {
        var media = new InstallerMedia ();
        yield media.setup_for_path (path, os_db, client, cancellable);

        if (media.os == null)
            return media;

        switch (media.os.short_id) {
        case "fedora14":
        case "fedora15":
        case "fedora16":
            media = new FedoraInstaller.copy (media);

            break;

        case "win7":
        case "win2k8":
            media = new Win7Installer.copy (media);

            break;

        case "winxp":
        case "win2k":
        case "win2k3":
            media = new WinXPInstaller.copy (media);

            break;

        default:
            return media;
        }

        return media;
    }

    private async void setup_for_path (string       path,
                                       OSDatabase   os_db,
                                       Client       client,
                                       Cancellable? cancellable) throws GLib.Error {
        var device = yield get_device_from_path (path, client, cancellable);

        if (device != null)
            get_media_info_from_device (device, os_db);
        else {
            from_image = true;
            os = yield os_db.guess_os_from_install_media (device_file, out os_media, cancellable);
        }

        if (os != null)
            label = os.get_name ();

        if (label == null)
            label = Path.get_basename (device_file);
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

        var os_id = device.get_property ("OSINFO_INSTALLER");
        if (os_id != null) {
            os = os_db.get_os_by_id (os_id);

            var media_id = device.get_property ("OSINFO_MEDIA");
            if (media_id != null)
                os_media = os_db.get_media_by_id (os, media_id);
        }
    }
}
