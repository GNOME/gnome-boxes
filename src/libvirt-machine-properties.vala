// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;
using Gtk;

private class Boxes.LibvirtMachineProperties: GLib.Object, Boxes.IPropertiesProvider {
    private weak LibvirtMachine machine; // Weak ref for avoiding cyclic ref */
    private uint shutdown_timeout;

    public LibvirtMachineProperties (LibvirtMachine machine) {
        this.machine = machine;
    }

    public bool try_change_name (string name) {
        try {
            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            // Te use libvirt "title" for free form user name
            config.title = name;
            // This will take effect only after next reboot, but we use pending/inactive config for name and title
            machine.domain.set_config (config);

            machine.name = name;
            return true;
        } catch (GLib.Error error) {
            warning ("Failed to change title of box '%s' to '%s': %s",
                     machine.domain.get_name (), name, error.message);
            return false;
        }
    }

    public void try_enable_usb_redir () throws GLib.Error {
        var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);

        // Remove any old usb configuration from old config
        VMConfigurator.remove_usb_controllers (config);

        // Add usb redirection channel and usb2 controllers
        VMConfigurator.add_usb_support (config);

        // This will take effect only after next reboot
        machine.domain.set_config (config);
        if (machine.is_on ())
            notify_reboot_required ();
    }

    public void try_enable_smartcard () throws GLib.Error {
        var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);

        VMConfigurator.add_smartcard_support (config);

        // This will take effect only after next reboot
        machine.domain.set_config (config);
        if (machine.is_on ())
            notify_reboot_required ();
    }

    private string collect_logs () {
        var builder = new StringBuilder ();

        builder.append_printf ("Domain: %s\n", machine.domain.get_name ());
        builder.append_printf ("UUID: %s\n", machine.domain.get_uuid ());
        builder.append_printf ("Persistent: %s\n", machine.domain.get_persistent () ? "yes" : "no");
        try {
            var info = machine.domain.get_info ();
            builder.append_printf ("Cpu time: %"+uint64.FORMAT_MODIFIER+"d\n", info.cpuTime);
            builder.append_printf ("Memory: %"+uint64.FORMAT_MODIFIER+"d\n", info.memory);
            builder.append_printf ("Max memory: %"+uint64.FORMAT_MODIFIER+"d\n", info.maxMem);
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

    public List<Boxes.Property> get_properties (Boxes.PropertiesPage page, PropertyCreationFlag flags) {
        var list = new List<Boxes.Property> ();

        // the wizard may want to modify display properties, before connect_display()
        if (machine.display == null)
            try {
                machine.update_display ();
            } catch (GLib.Error e) {
                warning (e.message);
            }

        switch (page) {
        case PropertiesPage.LOGIN:
            var property = add_string_property (ref list, _("Name"), machine.name);
            property.editable = true;
            property.changed.connect ((property, name) => {
                return try_change_name (name);
            });
            add_string_property (ref list, _("Virtualizer"), machine.source.uri);
            if (machine.display != null)
                property = add_string_property (ref list, _("URI"), machine.display.uri);
            break;

        case PropertiesPage.SYSTEM:
            add_ram_property (ref list);
            add_storage_property (ref list);

            var button = new Gtk.Button.with_label (_("Troubleshooting log"));
            button.halign = Gtk.Align.START;
            add_property (ref list, null, button);
            button.clicked.connect (() => {
                var log = collect_logs ();
                var dialog = new Gtk.Dialog.with_buttons (_("Troubleshooting log"),
                                                          App.app.window,
                                                          DialogFlags.DESTROY_WITH_PARENT,
                                                          Stock.SAVE, 100,
                                                          _("Copy to clipboard"), 101,
                                                          Stock.CLOSE, ResponseType.OK);
                dialog.set_default_size (640, 480);
                var text = new Gtk.TextView ();
                text.editable = false;
                var scroll = new Gtk.ScrolledWindow (null, null);
                scroll.add (text);
                scroll.vexpand = true;

                dialog.get_content_area ().add (scroll);
                text.buffer.set_text (log);
                dialog.show_all ();

                dialog.response.connect ( (response_id) => {
                    if (response_id == 100) {
                        var chooser = new Gtk.FileChooserDialog (_("Save log"), App.app.window,
                                                                 Gtk.FileChooserAction.SAVE,
                                                                 Stock.SAVE, ResponseType.OK);
                        chooser.local_only = false;
                        chooser.do_overwrite_confirmation = true;
                        chooser.response.connect ((response_id) => {
                            if (response_id == ResponseType.OK) {
                                var file = chooser.get_file ();
                                try {
                                    file.replace_contents (log.data, null, false,
                                                           FileCreateFlags.REPLACE_DESTINATION, null);
                                } catch (GLib.Error e) {
                                    var m = new Gtk.MessageDialog (chooser,
                                                                   Gtk.DialogFlags.DESTROY_WITH_PARENT,
                                                                   Gtk.MessageType.ERROR,
                                                                   Gtk.ButtonsType.CLOSE,
                                                                   _("Error saving: %s").printf (e.message));
                                    m.show_all ();
                                    m.response.connect ( () => { m.destroy (); });
                                    return;
                                }
                                chooser.destroy ();
                            } else {
                                chooser.destroy ();
                            }
                        });
                        chooser.show_all ();
                    } else if (response_id == 101){
                        Gtk.Clipboard.get_for_display (dialog.get_display (), Gdk.SELECTION_CLIPBOARD).set_text (log, -1);
                    } else {
                        dialog.destroy ();
                    }
                });
            });
            break;

        case PropertiesPage.DISPLAY:
            if (machine.display != null)
                add_string_property (ref list, _("Protocol"), machine.display.protocol);
            break;

        case PropertiesPage.DEVICES:
            foreach (var device_config in machine.domain_config.get_devices ()) {
                if (!(device_config is GVirConfig.DomainDisk))
                    continue;
                var disk_config = device_config as GVirConfig.DomainDisk;
                var disk_type = disk_config.get_guest_device_type ();
                if (disk_type == GVirConfig.DomainDiskGuestDeviceType.CDROM) {
                    var grid = new Gtk.Grid ();
                    grid.set_orientation (Gtk.Orientation.HORIZONTAL);
                    grid.set_column_spacing (12);

                    var label = new Gtk.Label ("");
                    grid.add (label);

                    var source = disk_config.get_source ();
                    bool empty = (source == null || source == "");

                    var button_label = new Gtk.Label ("");
                    var button = new Gtk.Button ();
                    button.add (button_label);

                    grid.add (button);

                    if (empty) {
                        // Translators: This is the text on the button to select an iso for the cd
                        button_label.set_text (_("Select"));
                        // Translators: empty is listed as the filename for a non-mounted CD
                        label.set_markup (Markup.printf_escaped ("<i>%s</i>", _("empty")));
                    } else {
                        // Translators: Remove is the label on the button to remove an iso from a cdrom drive
                        button_label.set_text (_("Remove"));
                        label.set_text (get_utf8_basename (source));
                    }

                    button.clicked.connect ( () => {
                        if (empty) {
                            var dialog = new Gtk.FileChooserDialog (_("Select a device or ISO file"),
                                                                    App.app.window,
                                                                    Gtk.FileChooserAction.OPEN,
                                                                    Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                                                                    Gtk.Stock.OPEN, Gtk.ResponseType.ACCEPT);
                            dialog.modal = true;
                            dialog.show_hidden = false;
                            dialog.local_only = true;
                            dialog.filter = new Gtk.FileFilter ();
                            dialog.filter.add_mime_type ("application/x-cd-image");
                            dialog.response.connect ( (response) => {
                                if (response == Gtk.ResponseType.ACCEPT) {
                                    var path = dialog.get_filename ();
                                    disk_config.set_source (path);
                                    try {
                                        machine.domain.update_device (disk_config, DomainUpdateDeviceFlags.CURRENT);
                                        button_label.set_text (_("Remove"));
                                        label.set_text (get_utf8_basename (path));
                                        empty = false;
                                    } catch (GLib.Error e) {
                                        machine.got_error (e.message);
                                    }
                                }
                                dialog.destroy ();
                            });
                            dialog.show_all ();
                        } else {
                            disk_config.set_source ("");
                            try {
                                machine.domain.update_device (disk_config, DomainUpdateDeviceFlags.CURRENT);
                                empty = true;
                                button_label.set_text (_("Select"));
                                label.set_markup (Markup.printf_escaped ("<i>%s</i>", _("empty")));
                            } catch (GLib.Error e) {
                                machine.got_error (e.message);
                            }
                        }
                    });

                    add_property (ref list, _("CD/DVD"), grid);
                }
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
                warning ("Failed to fetch configuration for domain '%s': %s", machine.domain.get_name (), error.message);
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
                    } catch (GLib.Error error) {
                        warning ("Failed to enable smartcard");
                    }
                });
            }

            break;
        }

        return list;
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

    private SizeProperty? add_ram_property (ref List<Boxes.Property> list) {
        try {
            var max_ram = machine.connection.get_node_info ().memory;

            var property = add_size_property (ref list,
                                              _("Memory"),
                                              machine.domain_config.memory,
                                              64 * Osinfo.MEBIBYTES,
                                              max_ram * Osinfo.KIBIBYTES,
                                              64 * Osinfo.MEBIBYTES);
            property.changed.connect (on_ram_changed);

            this.notify["state"].connect (() => {
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
            try {
                var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
                config.memory = value;
                if (config.get_class ().find_property ("current-memory") != null)
                    config.set ("current-memory", value);
                machine.domain.set_config (config);
                debug ("RAM changed to %llu", value);
                if (machine.is_on ())
                    notify_reboot_required ();
            } catch (GLib.Error error) {
                warning ("Failed to change RAM of box '%s' to %llu: %s",
                         machine.domain.get_name (),
                         value,
                         error.message);
            }

            if (machine.is_on ())
                update_ram_property (property);

            return false;
        };
    }

    private void notify_reboot_required () {
        Notificationbar.OKFunc reboot = () => {
            debug ("Rebooting '%s'..", machine.name);
            machine.stay_on_display = true;
            ulong state_id = 0;
            Gd.Notification notification = null;

            state_id = this.notify["state"].connect (() => {
                if (machine.state == Machine.MachineState.STOPPED ||
                    machine.state == Machine.MachineState.FORCE_STOPPED) {
                    debug ("'%s' stopped.", machine.name);
                    machine.start.begin ((obj, res) => {
                        try {
                            machine.start.end (res);
                        } catch (GLib.Error error) {
                            warning ("Failed to start '%s': %s", machine.domain.get_name (), error.message);
                        }
                    });
                    this.disconnect (state_id);
                    if (shutdown_timeout != 0) {
                        Source.remove (shutdown_timeout);
                        shutdown_timeout = 0;
                    }
                    if (notification != null) {
                        notification.dismiss ();
                        notification = null;
                    }
                }
            });

            shutdown_timeout = Timeout.add_seconds (5, () => {
                // Seems guest ignored ACPI shutdown, lets force shutdown with user's consent
                Notificationbar.OKFunc really_force_shutdown = () => {
                    notification = null;
                    machine.force_shutdown (false);
                };

                var message = _("Restart of '%s' is taking too long. Force it to shutdown?").printf (machine.name);
                notification = App.app.notificationbar.display_for_action (message,
                                                                           Gtk.Stock.YES,
                                                                           (owned) really_force_shutdown,
                                                                           null,
                                                                           -1);
                shutdown_timeout = 0;

                return false;
            });

            machine.try_shutdown ();
        };
        var message = _("Changes require restart of '%s'. Attempt restart?").printf (machine.name);
        App.app.notificationbar.display_for_action (message, Gtk.Stock.YES, (owned) reboot);
    }

    private SizeProperty? add_storage_property (ref List<Boxes.Property> list) {
        if (machine.storage_volume == null)
            return null;

        try {
            var volume_info = machine.storage_volume.get_info ();
            var pool = get_storage_pool (machine.connection);
            var pool_info = pool.get_info ();
            var max_storage = volume_info.capacity + pool_info.available;

            var property = add_size_property (ref list,
                                              _("Maximum Disk Size"),
                                              volume_info.capacity,
                                              volume_info.capacity,
                                              max_storage,
                                              256 * Osinfo.MEBIBYTES);
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
                    if (disk != null)
                        disk.resize (value, 0);
                } else
                    // Currently this never happens as properties page cant be reached without starting the machine
                    machine.storage_volume.resize (value, StorageVolResizeFlags.NONE);
                debug ("Storage changed to %llu", value);
            } catch (GLib.Error error) {
                warning ("Failed to change storage capacity of volume '%s' to %llu: %s",
                         machine.storage_volume.get_name (),
                         value,
                         error.message);
            }

            return false;
        };
    }
}
