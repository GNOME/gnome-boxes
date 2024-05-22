// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.StorageRow : Boxes.MemoryRow {
    private LibvirtMachine machine;

    private GVir.DomainDisk? external_disk;

    public void setup (LibvirtMachine machine) {
        this.machine = machine;

        bool storage_is_internal = (machine.storage_volume != null);
        if (!storage_is_internal) {
            try {
                external_disk = machine.get_domain_disk ();
            } catch (GLib.Error error) {
                warning ("Failed to obtain domain disk: %s", error.message);
                visible = false;

                return;
            }

        }

        bool has_disk = storage_is_internal || (external_disk != null);
        if (machine.importing || !has_disk) {
            visible = false;

            return;
        }

        if (storage_is_internal) {
            setup_internal_storage ();
        } else {
            setup_external_storage ();
        }
    }

    private void setup_internal_storage () {
        try {
            var volume_info = machine.storage_volume.get_info ();
            var pool = get_storage_pool (machine.connection);
            var pool_info = pool.get_info ();
            var min_storage = volume_info.allocation;
            var max_storage = min_storage + pool_info.available;

            // Translators: "%s" is a disk size string (for example "4.2 GB")
            subtitle = _("Used %s.").printf (GLib.format_size (volume_info.allocation));

            if (min_storage >= max_storage)
                subtitle = _("There is not enough space on your machine to increase the maximum disk size.");

            spin_button.set_range (min_storage, max_storage);
            spin_button.set_increments (256 * 1000 * 1000 , volume_info.allocation);
            spin_button.set_value (volume_info.capacity);
        } catch (GLib.Error error) {
            warning ("Failed to obtain virtual resources for '%s', %s",
                     machine.name,
                     error.message);
        }

        spin_button.value_changed.connect (on_spin_button_changed);
    }

    private void setup_external_storage () {
        var disk_config = external_disk.config as GVirConfig.DomainDisk;
        var disk = File.new_for_path (disk_config.get_source ());

        title = _("Storage disk");
        subtitle = disk.get_path ();

        disk.query_info_async.begin (FileAttribute.STANDARD_SIZE,
                               FileQueryInfoFlags.NONE,
                               Priority.LOW,
                               null, (obj, res) => {
            try {
                FileInfo info = disk.query_info_async.end (res);
                used_label.label = _("Used %s").printf (GLib.format_size (info.get_size (), GLib.FormatSizeFlags.IEC_UNITS));
            } catch (GLib.Error error) {
                message ("Failed to calculate disk size for '%s': %s", disk.get_path (),
                                                                       error.message);
                subtitle = error.message;
                used_label.visible = spin_button.visible = false;
            }
        });

        stack.set_visible_child (used_label);
    }

    private async void on_spin_button_changed () {
        uint64 storage = (uint64)spin_button.get_value ();

        try {
            if (!machine.is_running) {
                resize_storage_volume (storage);

                return;
            }

            var disk = machine.get_domain_disk ();
            if (disk == null)
                return;

            var size = (storage + Osinfo.KIBIBYTES - 1) / Osinfo.KIBIBYTES;
            disk.resize (size, GVir.StorageVolResizeFlags.SHRINK);

            var pool = get_storage_pool (machine.connection);
            yield pool.refresh_async (null);
            machine.update_domain_config ();
        } catch (GLib.Error error) {
            warning ("Failed to change storage capacity of volume '%s' to %" + uint64.FORMAT + " KiB: %s",
                     machine.storage_volume.get_name (),
                     storage,
                     error.message);
        }
    }

    private void resize_storage_volume (uint64 size) throws GLib.Error {
        var volume_info = machine.storage_volume.get_info ();
        if (machine.vm_creator != null && size < volume_info.capacity) {
            var config = machine.storage_volume.get_config (GVir.DomainXMLFlags.NONE);
            config.set_capacity (size);
            machine.storage_volume.delete (0);

            var pool = get_storage_pool (machine.connection);
            machine.storage_volume = pool.create_volume (config);
        } else {
            machine.storage_volume.resize (size, GVir.StorageVolResizeFlags.SHRINK);
        }

        debug ("Storage changed to %" + uint64.FORMAT, size);
    }
}
