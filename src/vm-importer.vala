// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVir;

private class Boxes.VMImporter : Boxes.VMCreator {
    public InstalledMedia source_media { get { return install_media as InstalledMedia; } }

    protected bool start_after_import = true;

    public VMImporter (InstalledMedia source_media) {
        base (source_media);
    }

    public VMImporter.for_import_completion (LibvirtMachine machine) {
        base.for_install_completion (machine);
    }

    public override void launch_vm (LibvirtMachine machine, int64 access_last_time = -1) throws GLib.Error {
        machine.vm_creator = this;
        machine.config.access_last_time = (access_last_time > 0)? access_last_time : get_real_time ();

        post_import_setup.begin (machine);
    }

    protected override async void continue_installation (LibvirtMachine machine) {
        install_media = yield MediaManager.get_instance ().create_installer_media_from_config (machine.domain_config);
        machine.vm_creator = this;

        yield post_import_setup (machine);
    }

    protected virtual async void post_import_setup (LibvirtMachine machine) {
        set_post_install_config (machine);

        if (start_after_import) {
            try {
                machine.domain.start (0);
            } catch (GLib.Error error) {
                warning ("Failed to start domain '%s': %s", machine.domain.get_name (), error.message);
            }
        }
        machine.vm_creator = null;
    }

    private async void import_vm (LibvirtMachine machine) {
        try {
            var destination_path = machine.storage_volume.get_path ();

            yield source_media.copy (destination_path);

            // Without refreshing the pool, libvirt will not know of changes to volume we just made
            yield Boxes.ensure_storage_pool (connection);
        } catch (GLib.Error error) {
            warning ("Failed to import box '%s' from file '%s': %s",
                     machine.name,
                     source_media.device_file,
                     error.message);
            var ui_message = _("Box import from file “%s” failed.").printf (source_media.device_file);
            App.app.main_window.notificationbar.display_error (ui_message);
            machine.delete ();

            return;
        }
    }
}
