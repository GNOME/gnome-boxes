// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.Main {
    private OSDatabase os_db;
    private VMCreator vm_creator;
    private GUdev.Client client;
    private MainLoop main_loop;
    private string[] paths;

    public Main (string[] paths) throws GLib.Error {
        os_db = new OSDatabase ();
        client = new GUdev.Client ({"block"});
        vm_creator = new VMCreator ("qemu:///session");
        main_loop = new MainLoop ();
        this.paths = paths;
    }

    public async void launch_new_vm_for_path (string path, Cancellable? cancellable) throws GLib.Error {
        var install_media = yield InstallerMedia.instantiate (path, os_db, client, cancellable);
        var resources = os_db.get_resources_for_os (install_media.os);
        var domain = yield vm_creator.create_domain_for_installer (install_media, resources, cancellable);

        domain.start (0);

        // Launch view to newly created VM
        var commandline = "virt-viewer --connect qemu:///session -w " + domain.get_uuid ();
        debug ("Launching: %s", commandline);
        var app = AppInfo.create_from_commandline (commandline, install_media.label, AppInfoCreateFlags.NONE);

        app.launch (null, null);
        debug ("Launched: %s", commandline);
    }

    public int run () {
        int ret = 0;
        uint8 vms_created = 0;

        foreach (var path in paths) {
            // FIXME: Work-around for bug#628336
            var _path = path;

            launch_new_vm_for_path.begin (path, null, (obj, res) => {
                try {
                    launch_new_vm_for_path.end (res);
                } catch (GLib.Error error) {
                    printerr ("Failed to create VM for '%s': %s", _path, error.message);

                    ret = -error.code;
                }

                vms_created++;

                if (vms_created == paths.length)
                    main_loop.quit ();
            });
        }

        main_loop.run ();

        return ret;
    }

    public static int main (string[] args) {
        try {
            var main = new Main (args[1:args.length]);

            return main.run ();
        } catch (GLib.Error error) {
            printerr ("Failed to initialize: %s", error.message);

            return -error.code;
        }
    }
}
