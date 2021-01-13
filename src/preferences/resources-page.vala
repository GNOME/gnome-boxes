// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/resources-page.ui")]
private class Boxes.PreferencesResourcesPage: Hdy.PreferencesPage {
    [GtkChild]
    private Gtk.Entry box_name_entry;
    [GtkChild]
    private Gtk.Switch accel_3d_toggle;

    [GtkChild]
    private Gtk.Button restart_button;
    [GtkChild]
    private Gtk.Button force_shutdown_button;

    [GtkChild]
    private Gtk.Box memory_widget;
    [GtkChild]
    private Gtk.Box storage_widget;
    [GtkChild]
    private Gtk.SpinButton cpus_spinbutton;
    [GtkChild]
    private Gtk.Switch run_in_bg_switch;

    private LibvirtMachine machine;

    public void setup (LibvirtMachine machine) {
        this.machine = machine;

        box_name_entry.set_text (machine.name);
        box_name_entry.bind_property ("text", machine, "name", BindingFlags.BIDIRECTIONAL);

        accel_3d_toggle.set_active (machine.acceleration_3d);
        accel_3d_toggle.bind_property ("active", machine, "acceleration-3d", BindingFlags.BIDIRECTIONAL);

#if FLATPAK
        if (accel_3d_toggle.get_active ())
            on_run_in_bg ();
#endif

        // Action buttons
        restart_button.sensitive = force_shutdown_button.sensitive = machine.is_running;
        machine.notify["state"].connect (on_machine_state_changed);

        var host_topology = machine.connection.get_node_info ();
        add_ram_property ();
        add_storage_property ();

        /* CPU property */
        var vcpus = machine.domain_config.get_vcpus ();
        var max_vcpus = host_topology.cores * host_topology.sockets * host_topology.threads;
        cpus_spinbutton.set_range (1, max_vcpus);
        cpus_spinbutton.set_value (vcpus);

        run_in_bg_switch.set_active (machine.run_in_bg);
        //run_in_bg_switch.bind_property ("active", machine, "run-in-bg", BindingFlags.BIDIRECTIONAL);

        run_in_bg_switch.notify["active"].connect (() => {
            var box = get_parent ().get_parent () as Gtk.Container;
            var infobar = new Gtk.InfoBar () {
                valign = Gtk.Align.START
            }; 
            infobar.add (new Gtk.Label ("TEST LABEL"));
            //box.pack_end (infobar, false, false, 0);
            box.add_with_properties (infobar, "position", 0, null);
            infobar.show_all ();
        });

    }

    private async void on_run_in_bg () {
        if (!machine.run_in_bg)
            return;

        yield Portals.get_default ().request_to_run_in_background (
        (response, results) => {
            if (response == 0) {
                debug ("User authorized Boxes to run in background");

                return;
            }

            try {
                machine.run_in_bg = false;

                var msg = _("Boxes is not authorized to run in the background");
                machine.window.notificationbar.display_for_action (msg,
                                                                   _("Manage permissions"),
                                                                   open_permission_settings);
            } catch (GLib.Error error) {
                warning ("Failed to reset VM's run-in-bg setting: %s", error.message);
            }
        });
    }

    private void on_machine_state_changed () {
        restart_button.sensitive = machine.is_running;
        force_shutdown_button.sensitive = machine.is_running;
    }

    [GtkCallback]
    private void on_restart_button_clicked () {
        machine.restart ();
    }

    [GtkCallback]
    private void on_force_shutdown_button_clicked () {
        machine.force_shutdown ();
    }

    private void add_ram_property () {
        try {
            var host_topology = machine.connection.get_node_info ();

            var min_ram = 64 * Osinfo.MEBIBYTES;
            var max_ram = host_topology.memory * Osinfo.KIBIBYTES;
            var size_ram = machine.domain_config.memory * Osinfo.KIBIBYTES;

            var ram_property = new SizeProperty ("ram", size_ram, min_ram, max_ram, 0, min_ram, GLib.FormatSizeFlags.IEC_UNITS);
            memory_widget.add (ram_property.extra_widget);
            ram_property.extra_widget.visible = true;

            if ((VMConfigurator.is_install_config (machine.domain_config) ||
                 VMConfigurator.is_live_config (machine.domain_config)) &&
                 machine.state != Machine.MachineState.FORCE_STOPPED)
                ram_property.sensitive = false;
            else
                ram_property.changed.connect ((property, value) => {
                    property.deferred_change = () => {
                        var ram = (value + Osinfo.KIBIBYTES - 1) / Osinfo.KIBIBYTES;
                        try {
                            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
                            config.memory = ram;
                            if (config.get_class ().find_property ("current-memory") != null)
                                config.set ("current-memory", ram);
                            machine.domain.set_config (config);
                            debug ("RAM changed to %llu KiB", ram);
                        } catch (GLib.Error error) {
                            warning ("Failed to change RAM of box '%s' to %llu KiB: %s",
                                     machine.domain.get_name (), ram, error.message);
                        }

                        update_ram_property (property);

                        return false;
                    };
                });

            machine.notify["state"].connect (() => {
                if (!machine.is_on)
                    ram_property.reboot_required = false;
            });

            update_ram_property (ram_property);
        } catch (GLib.Error error) {
            warning ("Failed to add RAM property: %s", error.message);
        }
    }

    private void update_ram_property (Boxes.Property property) {
        try {
            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);

            // we use KiB unit, convert to MiB
            var actual = machine.domain_config.memory / 1024;
            var pending = config.memory / 1024;

            debug ("RAM actual: %llu, pending: %llu", actual, pending);
            // somehow, there are rounded errors, so let's forget about 1Mb diff
            property.reboot_required = (actual - pending) > 1; // no need for abs()
        } catch (GLib.Error e) {}
    }

    private const uint64 MEGABYTES = 1000 * 1000;
    private void add_storage_property () {
        if (machine.importing || machine.storage_volume == null)
            return;

        try {
            var volume_info = machine.storage_volume.get_info ();
            var pool = get_storage_pool (machine.connection);
            var pool_info = pool.get_info ();
            var min_storage = get_minimum_disk_size ();
            var max_storage = volume_info.allocation + pool_info.available;

            if (min_storage >= max_storage) {
                var label = new Gtk.Label ("");
                var capacity = format_size (volume_info.capacity, FormatSizeFlags.DEFAULT);
                var allocation = format_size (volume_info.allocation, FormatSizeFlags.DEFAULT);
                var label_text = _("Maximum Disk Space");
                var allocation_text = _("%s used").printf (allocation);
                var markup = ("<span color=\"grey\">%s</span>\t\t %s <span color=\"grey\">(%s)</span>").printf (label_text, capacity, allocation_text);
                label.set_markup (markup);
                label.halign = Gtk.Align.START;

                storage_widget.add (label);

                var infobar = new Gtk.InfoBar ();
                infobar.message_type = Gtk.MessageType.WARNING;

                var content = infobar.get_content_area ();

                var image = new Gtk.Image ();
                image.icon_name = "dialog-warning";
                image.icon_size = 3;
                content.add (image);

                var msg = _("There is not enough space on your machine to increase the maximum disk size.");
                label = new Gtk.Label (msg);
                content.add (label);

                //add_property (ref list, null, infobar);
                storage_widget.add (infobar);
            }

            var property = new SizeProperty ("storage",
                                             volume_info.capacity,
                                             min_storage,
                                             max_storage,
                                             volume_info.allocation,
                                             256 * MEGABYTES,
                                             GLib.FormatSizeFlags.DEFAULT);

            // Disable 'save on timeout' all together since that could lead us to very bad user experience:
            // You accidently increase the capacity to too high value and if you are not quick enough to change
            // it again, you'll not be able to correct this ever as we don't support shrinking of volumes.
            property.defer_interval = 0;
            if ((VMConfigurator.is_install_config (machine.domain_config) ||
                 VMConfigurator.is_live_config (machine.domain_config)) &&
                machine.window.ui_state != Boxes.UIState.WIZARD &&
                machine.state != Machine.MachineState.FORCE_STOPPED)
                property.sensitive = false;
            else
                property.changed.connect (on_storage_changed);

            storage_widget.add (property.extra_widget);
            storage_widget.show_all ();
        } catch (GLib.Error error) {
            warning ("Failed to get information on volume '%s' or it's parent pool: %s",
                     machine.storage_volume.get_name (),
                     error.message);
        }
    }

    private async void change_storage_size (Boxes.Property property, uint64 value) {
        if (machine.storage_volume == null)
            return;

        List<GVir.DomainSnapshot> snapshots;
        try {
            snapshots = yield get_snapshots (null);
        } catch (GLib.Error e) {
            warning ("Error fetching snapshots for %s: %s", machine.name, e.message);
            snapshots = new List<GVir.DomainSnapshot> ();
        }

        var num_snapshots = snapshots.length ();
        if (num_snapshots != 0) {
            // qemu-img doesn't support resizing disk image with snapshots:
            // https://bugs.launchpad.net/qemu/+bug/1563931
            var msg = ngettext ("Storage resize requires deleting associated snapshot.",
                                "Storage resize requires deleting %llu associated snapshots.",
                                num_snapshots).printf (num_snapshots);

            Notification.OKFunc undo = () => {
                debug ("Storage resize of '%s' cancelled by user.", machine.name);
            };

            Notification.DismissFunc really_resize = () => {
                debug ("User did not cancel storage resize of '%s'. Deleting all snapshots..", machine.name);
                force_change_storage_size.begin (property, value);
            };

            machine.window.notificationbar.display_for_action (msg, _("_Undo"), (owned) undo, (owned) really_resize);

            return;
        }

        try {
            if (machine.is_running) {
                var disk = machine.get_domain_disk ();
                if (disk == null)
                    return;

                var size = (value + Osinfo.KIBIBYTES - 1) / Osinfo.KIBIBYTES;
                disk.resize (size, 0);

                var pool = get_storage_pool (machine.connection);
                try {
                  yield pool.refresh_async (null);
                  machine.update_domain_config ();
                  debug ("Storage changed to %llu KiB", size);
                } catch (GLib.Error error) {
                  warning ("Failed to change storage capacity of volume '%s' to %llu KiB: %s",
                           machine.storage_volume.get_name (),
                           size,
                           error.message);
                }
            } else {
                resize_storage_volume (value);
                debug ("Storage changed to %llu", value);
            }
        } catch (GLib.Error error) {
            warning ("Failed to change storage capacity of volume '%s' to %llu: %s",
                    machine.storage_volume.get_name (),
                    value,
                    error.message);
        }
    }

    private async void force_change_storage_size (Boxes.Property property, uint64 value) {
        try {
            var snapshots = yield get_snapshots (null);

            foreach (var snapshot in snapshots) {
                yield snapshot.delete_async (0, null);
            }

            change_storage_size.begin (property, value);
        } catch (GLib.Error e) {
            warning ("Error while deleting snapshots: %s", e.message);
        }
    }

    private uint64 get_minimum_disk_size () throws GLib.Error {
        var volume_info = machine.storage_volume.get_info ();
        if (machine.vm_creator == null) {
            // Since we disable the properties during install going on we don't need to check for
            // previous_ui_state here to be WIZARD.
            return volume_info.capacity;
        }

        Osinfo.Resources minimum_resources = null;

        if (machine.vm_creator.install_media.os != null) {
            var os = machine.vm_creator.install_media.os;
            var architecture = machine.domain_config.get_os ().get_arch ();
            minimum_resources = OSDatabase.get_minimum_resources_for_os (os, architecture);
        }

        if (minimum_resources != null && minimum_resources.storage != -1) {
            return minimum_resources.storage;
        } else {
            minimum_resources = OSDatabase.get_minimum_resources ();
            return uint64.min (volume_info.capacity, minimum_resources.storage);
        }
    }

    private void resize_storage_volume (uint64 size) throws GLib.Error {
        var volume_info = machine.storage_volume.get_info ();
        if (machine.vm_creator != null && size < volume_info.capacity) {
            // New VM Customization
            var config = machine.storage_volume.get_config (GVir.DomainXMLFlags.NONE);
            config.set_capacity (size);
            machine.storage_volume.delete (0);

            var pool = get_storage_pool (machine.connection);
            machine.storage_volume = pool.create_volume (config);
        } else {
            machine.storage_volume.resize (size, GVir.StorageVolResizeFlags.NONE);
        }
    }

    private void on_storage_changed (Boxes.Property property, uint64 value) {
        // Ensure that we don't end-up changing storage like a 1000 times a second while user moves the slider..
        property.deferred_change = () => {
            change_storage_size.begin (property, value);

            return false;
        };
    }

    public async List<GVir.DomainSnapshot>? get_snapshots (GLib.Cancellable? cancellable) throws GLib.Error {
        yield machine.domain.fetch_snapshots_async (GVir.DomainSnapshotListFlags.ALL, cancellable);

        return machine.domain.get_snapshots ();
    }
}
