// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;
using Gtk;

private class Boxes.LibvirtMachineProperties: GLib.Object, Boxes.IPropertiesProvider {
    private const uint64 MEGABYTES = 1000 * 1000;

    private weak LibvirtMachine machine; // Weak ref for avoiding cyclic ref */

    public LibvirtMachineProperties (LibvirtMachine machine) {
        this.machine = machine;

        machine.notify["name"].connect (() => {
            save_machine_name_change ();
        });
    }

    private bool save_machine_name_change () {
        try {
            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            // Te use libvirt "title" for free form user name
            config.title = machine.name;
            // This will take effect only after next reboot, but we use pending/inactive config for name and title
            machine.domain.set_config (config);

            return true;
        } catch (GLib.Error error) {
            warning ("Failed to save change of title of box from '%s' to '%s': %s",
                     machine.domain.get_name (), machine.name, error.message);
            return false;
        }
    }

    private void try_enable_usb_redir () throws GLib.Error {
        var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);

        // Remove any old usb configuration from old config
        VMConfigurator.remove_usb_controllers (config);

        // Add usb redirection channel and usb2 controllers
        VMConfigurator.add_usb_support (config);

        // This will take effect only after next reboot
        machine.domain.set_config (config);
    }

    private void try_enable_smartcard () throws GLib.Error {
        var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);

        VMConfigurator.add_smartcard_support (config);

        // This will take effect only after next reboot
        machine.domain.set_config (config);
    }

    private string collect_logs () {
        var builder = new StringBuilder ();

        builder.append_printf ("Broker URL: %s\n", machine.source.uri);
        builder.append_printf ("Domain: %s\n", machine.domain.get_name ());
        builder.append_printf ("UUID: %s\n", machine.domain.get_uuid ());
        builder.append_printf ("Persistent: %s\n", machine.domain.get_persistent () ? "yes" : "no");
        try {
            var info = machine.domain.get_info ();
            builder.append_printf ("Cpu time: %"+uint64.FORMAT_MODIFIER+"d\n", info.cpuTime);
            builder.append_printf ("Memory: %"+uint64.FORMAT_MODIFIER+"d KiB\n", info.memory);
            builder.append_printf ("Max memory: %"+uint64.FORMAT_MODIFIER+"d KiB\n",
                                   machine.connection.get_node_info ().memory);
            builder.append_printf ("CPUs: %d\n", info.nrVirtCpu);
            builder.append_printf ("State: %s\n", info.state.to_string ());
        } catch (GLib.Error e) {
        }

        if (machine.display != null)
            machine.display.collect_logs (builder);


        try {
            var conf = machine.domain.get_config (GVir.DomainXMLFlags.NONE);
            builder.append_printf ("\nDomain config:\n");
            builder.append_printf ("------------------------------------------------------------\n");

            builder.append (conf.to_xml ());
            builder.append_printf ("\n" +
                                   "------------------------------------------------------------\n");
        } catch (GLib.Error error) {
        }

        try {
            var logfile = Path.build_filename (Environment.get_user_cache_dir (),
                                               "libvirt/qemu/log",
                                               machine.domain.get_name ()  + ".log");
            string data;
            FileUtils.get_contents (logfile, out data);
            builder.append_printf ("\nQEMU log:\n");
            builder.append_printf ("------------------------------------------------------------\n");

            builder.append (data);
            builder.append_printf ("------------------------------------------------------------\n");
        } catch (GLib.Error e) {
        }
        return builder.str;
    }

    public List<Boxes.Property> get_properties (Boxes.PropertiesPage page, ref PropertyCreationFlag flags) {
        var list = new List<Boxes.Property> ();

        // the wizard may want to modify display properties, before connect_display()
        if (machine.is_on () && machine.display == null)
            try {
                machine.update_display ();
            } catch (GLib.Error e) {
                warning (e.message);
            }

        switch (page) {
        case PropertiesPage.GENERAL:
            var property = add_editable_string_property (ref list, _("Name"), machine.name);
            property.changed.connect ((property, name) => {
                machine.name = name;
            });

            var name_property = property;
            machine.notify["name"].connect (() => {
                name_property.text = machine.name;
            });

            add_string_property (ref list, _("Broker"), machine.source.name);
            if (machine.display != null) {
                add_string_property (ref list, _("Protocol"), machine.display.protocol);
                add_string_property (ref list, _("URI"), machine.display.uri);
            }
            break;

        case PropertiesPage.SYSTEM:
            add_resource_usage_graphs (ref list);

            add_system_props_buttons (ref list);

            get_resources_properties (ref list);

            break;

        case PropertiesPage.DEVICES:
            foreach (var device_config in machine.domain_config.get_devices ()) {
                if (!(device_config is GVirConfig.DomainDisk))
                    continue;
                var disk_config = device_config as GVirConfig.DomainDisk;
                var disk_type = disk_config.get_guest_device_type ();
                if (disk_type == GVirConfig.DomainDiskGuestDeviceType.CDROM)
                    add_cdrom_property (disk_config, ref list);
            }

            bool has_usb_redir = false;
            bool has_smartcard = false;
            // We look at the INACTIVE config here, because we want to show the usb
            // widgetry if usb has been added already but we have not rebooted
            try {
                var inactive_config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
                foreach (var device in inactive_config.get_devices ()) {
                    if (device is GVirConfig.DomainRedirdev) {
                        has_usb_redir = true;
                    }
                    if (device is GVirConfig.DomainSmartcard) {
                        has_smartcard = true;
                    }
                }
            } catch (GLib.Error error) {
                warning ("Failed to fetch configuration for domain '%s': %s",
                         machine.domain.get_name (),
                         error.message);
            }

            if (!has_usb_redir)
                flags |= PropertyCreationFlag.NO_USB;

            /* Only add usb support to guests if HAVE_USBREDIR, as older
             * qemu versions break migration with it. */
            if (!has_usb_redir && Config.HAVE_USBREDIR) {
                var button = new Gtk.Button.with_label (_("Add support to guest"));
                button.halign = Gtk.Align.START;
                var property = add_property (ref list, _("USB device support"), button);
                button.clicked.connect (() => {
                    try {
                        try_enable_usb_redir ();
                        machine.update_domain_config ();
                        property.refresh_properties ();
                        property.reboot_required = true;
                    } catch (GLib.Error error) {
                        warning ("Failed to enable usb");
                    }
                });
            }

            // Only add smartcart support to guests if HAVE_SMARTCARD, as qemu built
            // without smartcard support will not start vms with it.
            if (!has_smartcard && Config.HAVE_SMARTCARD) {
                var button = new Gtk.Button.with_label (_("Add support to guest"));
                button.halign = Gtk.Align.START;
                var property = add_property (ref list, _("Smartcard support"), button);
                button.clicked.connect (() => {
                    try {
                        try_enable_smartcard ();
                        machine.update_domain_config ();
                        property.refresh_properties ();
                        property.reboot_required = true;
                    } catch (GLib.Error error) {
                        warning ("Failed to enable smartcard");
                    }
                });
            }

            break;

        case PropertiesPage.SNAPSHOTS:
            try {
                var config = machine.domain.get_config (0);
                // Snapshots currently don't work with host-passthrough
                if (config.get_cpu ().get_mode () != GVirConfig.DomainCpuMode.HOST_PASSTHROUGH &&
                    !VMConfigurator.is_install_config (config))
                    add_snapshots_property (ref list, machine);
            } catch (GLib.Error e) {
                warning (e.message);
            }

            break;
        }

        return list;
    }

    public void get_resources_properties (ref List<Boxes.Property> list) {
        var ram_property = add_ram_property (ref list);
        var storage_property = add_storage_property (ref list);
        mark_recommended_resources.begin (ram_property, storage_property);
    }

    private void add_cdrom_property (GVirConfig.DomainDisk disk_config, ref List<Boxes.Property> list) {
        var grid = new Gtk.Grid ();
        grid.set_orientation (Gtk.Orientation.HORIZONTAL);
        grid.set_column_spacing (12);

        var label = new Gtk.Label ("");
        label.set_ellipsize (Pango.EllipsizeMode.END);
        grid.add (label);

        var source = disk_config.get_source ();
        bool empty = (source == null || source == "");

        if (empty)
            // Translators: empty is listed as the filename for a non-mounted CD
            label.set_markup (Markup.printf_escaped ("<i>%s</i>", _("empty")));
        else
            label.set_text (get_utf8_basename (source));

        if (machine.vm_creator != null) {
            var media = machine.vm_creator.install_media;

            if (machine.vm_creator.express_install || (media.os_media != null && media.os_media.live)) {
                // Don't let user eject installer media if its an express installation or a live media
                add_property (ref list, _("CD/DVD"), grid);

                return;
            }
        }

        var button_label = new Gtk.Label ("");
        var button = new Gtk.Button ();
        button.add (button_label);

        grid.add (button);

        if (empty)
            // Translators: This is the text on the button to select an iso for the cd
            button_label.set_text (_("Select"));
        else
            // Translators: Remove is the label on the button to remove an iso from a cdrom drive
            button_label.set_text (_("Remove"));

        button.clicked.connect ( () => {
            if (empty) {
                machine.window.props_window.show_file_chooser ((path) => {
                    disk_config.set_source (path);
                    try {
                        machine.domain.update_device (disk_config, DomainUpdateDeviceFlags.CURRENT);
                        button_label.set_text (_("Remove"));
                        label.set_text (get_utf8_basename (path));
                        empty = false;
                    } catch (GLib.Error e) {
                        var path_basename = get_utf8_basename (path);
                        // Translators: First '%s' is filename of ISO or CD/DVD device that user selected and
                        //              Second '%s' is name of the box.
                        var msg = _("Insertion of '%s' as a CD/DVD into '%s' failed");
                        machine.got_error (msg.printf (path_basename, machine.name));
                        debug ("Error inserting '%s' as CD into '%s': %s", path_basename, machine.name, e.message);
                    }
                });
            } else {
                disk_config.set_source ("");
                try {
                    machine.domain.update_device (disk_config, DomainUpdateDeviceFlags.CURRENT);
                    empty = true;
                    button_label.set_text (_("Select"));
                    label.set_markup (Markup.printf_escaped ("<i>%s</i>", _("empty")));
                } catch (GLib.Error e) {
                    // Translators: '%s' here is name of the box.
                    machine.got_error (_("Removal of CD/DVD from '%s' failed").printf (machine.name));
                    debug ("Error ejecting CD from '%s': %s", machine.name, e.message);
                }
            }
        });

        var property = add_property (ref list, _("CD/DVD"), grid);
        property.description_alignment = Gtk.Align.START;
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

    private async void mark_recommended_resources (SizeProperty? ram_property, SizeProperty? storage_property) {
        if (ram_property == null && storage_property == null)
            return;

        var os = yield get_os_for_machine (machine);
        if (os == null)
            return;

        var architecture = machine.domain_config.get_os ().get_arch ();
        var resources = OSDatabase.get_recommended_resources_for_os (os, architecture);
        if (resources != null) {
            if (ram_property != null)
                ram_property.recommended = resources.ram;
            if (storage_property != null)
                storage_property.recommended = resources.storage;
        }
    }

    private async Osinfo.Os? get_os_for_machine (LibvirtMachine machine) {
        var os_id = VMConfigurator.get_os_id (machine.domain_config);
        if (os_id == null)
            return null;

        var os_db = MediaManager.get_instance ().os_db;
        try {
            return yield os_db.get_os_by_id (os_id);
        } catch (OSDatabaseError error) {
            warning ("Failed to find OS with ID '%s': %s", os_id, error.message);
            return null;
        }
    }

    private void add_resource_usage_graphs (ref List<Boxes.Property> list) {
        var grid = new Gtk.Grid ();
        grid.row_spacing = 5;
        grid.column_spacing = 10;
        grid.column_homogeneous = true;
        grid.vexpand = false;

        // CPU
        var cpu_graph = new MiniGraph (100);
        cpu_graph.npoints = 20;
        grid.attach (cpu_graph, 0, 0, 1, 1);
        var label = new Gtk.Label (_("CPU"));
        grid.attach (label, 0, 1, 1, 1);

        // I/O
        var io_graph = new MiniGraph (20);
        grid.attach (io_graph, 1, 0, 1, 1);
        label = new Gtk.Label (_("I/O"));
        grid.attach (label, 1, 1, 1, 1);

        // Network
        var net_graph = new MiniGraph (20);
        grid.attach (net_graph, 2, 0, 1, 1);
        label = new Gtk.Label (_("Network"));
        grid.attach (label, 2, 1, 1, 1);

        var stats_id = machine.stats_updated.connect (() => {
            cpu_graph.points = machine.cpu_stats;
            io_graph.points = machine.io_stats;
            net_graph.points = machine.net_stats;
        });

        var prop = add_property (ref list, null, grid);
        ulong flushed_id = 0;
        flushed_id = prop.flushed.connect (() => {
            machine.disconnect (stats_id);
            prop.disconnect (flushed_id);
        });
    }

    private void add_system_props_buttons (ref List<Boxes.Property> list) {
        var grid = new Gtk.Grid ();
        grid.margin_top = 5;
        grid.column_spacing = 5;
        grid.halign = Gtk.Align.START;

        var button = new Gtk.Button.with_label (_("Troubleshooting log"));
        grid.attach (button, 0, 0, 1, 1);
        button.clicked.connect (() => {
            var log = collect_logs ();
            machine.window.props_window.show_troubleshoot_log (log);
        });

        button = new Gtk.Button.with_label (_("Force Shutdown"));
        button.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
        button.clicked.connect (() => {
            machine.force_shutdown ();
        });
        grid.attach (button, 1, 0, 1, 1);

        button.sensitive = machine.is_running ();
        var state_notify_id = machine.notify["state"].connect (() => {
            button.sensitive = machine.is_running ();
        });

        var prop = add_property (ref list, null, grid);
        ulong flushed_id = 0;
        flushed_id = prop.flushed.connect (() => {
            machine.disconnect (state_notify_id);
            prop.disconnect (flushed_id);
        });
    }

    private SizeProperty? add_ram_property (ref List<Boxes.Property> list) {
        try {
            var max_ram = machine.connection.get_node_info ().memory;

            var property = add_size_property (ref list,
                                              _("Memory"),
                                              machine.domain_config.memory * Osinfo.KIBIBYTES,
                                              64 * Osinfo.MEBIBYTES,
                                              max_ram * Osinfo.KIBIBYTES,
                                              0,
                                              64 * Osinfo.MEBIBYTES,
                                              FormatSizeFlags.IEC_UNITS);
            property.description_alignment = Gtk.Align.START;
            property.widget.margin_top = 5;
            if ((VMConfigurator.is_install_config (machine.domain_config) ||
                 VMConfigurator.is_live_config (machine.domain_config)) &&
                machine.window.ui_state != Boxes.UIState.WIZARD)
                property.sensitive = false;
            else
                property.changed.connect (on_ram_changed);

            machine.notify["state"].connect (() => {
                if (!machine.is_on ())
                    property.reboot_required = false;
            });

            update_ram_property (property);

            return property;
        } catch (GLib.Error error) {
            return null;
        }
    }

    private void on_ram_changed (Boxes.Property property, uint64 value) {
        // Ensure that we don't end-up changing RAM like a 1000 times a second while user moves the slider..
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
                         machine.domain.get_name (),
                         ram,
                         error.message);
            }

            update_ram_property (property);

            return false;
        };
    }

    private SizeProperty? add_storage_property (ref List<Boxes.Property> list) {
        if (machine.importing || machine.storage_volume == null)
            return null;

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
                var markup = _("<span color=\"grey\">Maximum Disk Size</span>\t\t %s <span color=\"grey\">(%s used)</span>").printf (capacity, allocation);
                label.set_markup (markup);
                label.halign = Gtk.Align.START;

                add_property (ref list, null, label);

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

                add_property (ref list, null, infobar);
                return null;
            }

            var property = add_size_property (ref list,
                                              _("Maximum Disk Size"),
                                              volume_info.capacity,
                                              min_storage,
                                              max_storage,
                                              volume_info.allocation,
                                              256 * MEGABYTES);
            property.description_alignment = Gtk.Align.START;
            // Disable 'save on timeout' all together since that could lead us to very bad user experience:
            // You accidently increase the capacity to too high value and if you are not quick enough to change
            // it again, you'll not be able to correct this ever as we don't support shrinking of volumes.
            property.defer_interval = 0;
            if ((VMConfigurator.is_install_config (machine.domain_config) ||
                 VMConfigurator.is_live_config (machine.domain_config)) &&
                machine.window.ui_state != Boxes.UIState.WIZARD)
                property.sensitive = false;
            else
                property.changed.connect (on_storage_changed);

            return property;
        } catch (GLib.Error error) {
            warning ("Failed to get information on volume '%s' or it's parent pool: %s",
                     machine.storage_volume.get_name (),
                     error.message);
            return null;
        }
    }

    private void on_storage_changed (Boxes.Property property, uint64 value) {
        // Ensure that we don't end-up changing storage like a 1000 times a second while user moves the slider..
        property.deferred_change = () => {
            if (machine.storage_volume == null)
                return false;

            try {
                if (machine.is_running ()) {
                    var disk = machine.get_domain_disk ();
                    if (disk != null) {
                        var size = (value + Osinfo.KIBIBYTES - 1) / Osinfo.KIBIBYTES;
                        disk.resize (size, 0);

                        var pool = get_storage_pool (machine.connection);
                        pool.refresh_async.begin (null, (obj, res) => {
                            try {
                                pool.refresh_async.end (res);
                                machine.update_domain_config ();
                                debug ("Storage changed to %llu KiB", size);
                            } catch (GLib.Error error) {
                                warning ("Failed to change storage capacity of volume '%s' to %llu KiB: %s",
                                         machine.storage_volume.get_name (),
                                         size,
                                         error.message);
                            }
                        });
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

            return false;
        };
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
            var default_resources = OSDatabase.get_default_resources ();
            return uint64.min (volume_info.capacity, default_resources.storage);
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
            machine.storage_volume.resize (size, StorageVolResizeFlags.NONE);
        }
    }

    public async void fetch_snapshots (GLib.Cancellable? cancellable) throws GLib.Error {
        yield machine.domain.fetch_snapshots_async (GVir.DomainSnapshotListFlags.ALL, cancellable);
    }

    public List<GVir.DomainSnapshot>? get_snapshots () {
        return machine.domain.get_snapshots ();
    }

    public async GVir.DomainSnapshot create_snapshot () throws GLib.Error {
        var config = new GVirConfig.DomainSnapshot ();
        var now = new GLib.DateTime.now_local ();
        config.set_name (now.format ("%F-%H-%M-%S"));
        config.set_description (now.format ("%x, %X"));

        return yield machine.domain.create_snapshot_async (config, 0, null);
    }

    private Boxes.SnapshotsProperty add_snapshots_property (ref List<Boxes.Property> list,
                                                            LibvirtMachine           machine) {
      var property = new SnapshotsProperty (machine);
      list.append (property);

      return property;
    }


}
