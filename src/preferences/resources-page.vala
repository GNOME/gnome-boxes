// This file is part of GNOME Boxes. License: LGPLv2+
using GLib;
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/resources-page.ui")]
private class Boxes.ResourcesPage : Hdy.PreferencesPage {
    private LibvirtMachine machine;

    private FileMonitor config_file_monitor;

    private string logs;

    [GtkChild]
    private unowned Boxes.VMNameRow box_name_entry;

    [GtkChild]
    private unowned Hdy.PreferencesGroup address_group;
    [GtkChild]
    private unowned Hdy.ActionRow ip_address_row;
    [GtkChild]
    private unowned Gtk.Label ip_address_label;

    [GtkChild]
    private unowned Hdy.PreferencesGroup resources_group;
    [GtkChild]
    private unowned Gtk.SpinButton cpus_spin_button;
    [GtkChild]
    private unowned Boxes.RamRow ram_row;
    [GtkChild]
    private unowned Boxes.StorageRow storage_row;
    [GtkChild]
    private unowned Hdy.ActionRow acceleration_3d_row;
    [GtkChild]
    private unowned Gtk.Switch acceleration_3d_toggle;

    [GtkChild]
    private unowned Gtk.Switch run_in_bg_toggle;

    public void setup (LibvirtMachine machine) {
        this.machine = machine;

        setup_address_group ();
        bind_widget_property (box_name_entry, "text", "title");
        bind_widget_property (run_in_bg_toggle, "active", "run-in-bg");

        on_run_in_bg_toggled.begin ();
        mark_recommended_resources.begin ();

        machine.supports_accel3d.begin ((source, result) => {
            acceleration_3d_row.visible = machine.supports_accel3d.end (result);
            if (acceleration_3d_row.visible)
                bind_widget_property (acceleration_3d_toggle,
                                      "active",
                                      "acceleration-3d");
        });

        ram_row.memory = machine.ram;
        bind_widget_property (ram_row, "memory", "ram");
        storage_row.setup (machine);
        setup_cpu_row ();

        machine.notify["is-running"].connect (on_machine_state_changed);
        on_machine_state_changed ();
    }

    private void setup_address_group () {
        string? address = machine.get_ip_address ();

        address_group.visible = ip_address_row.visible = address != null;
        ip_address_label.label = address;
    }

    private async void mark_recommended_resources () {
        var os = yield machine.get_os ();
        if (os == null)
            return;

        var architecture = machine.domain_config.get_os ().get_arch ();
        var recommended_resources = OSDatabase.get_recommended_resources_for_os (os, architecture);
        if (recommended_resources != null) {
            // Translators: %s is a recommended value for RAM/storage limit. For example "Recommended 4 GB."
            var row_subtitle = _("Recommended %s.");

            ram_row.set_subtitle (row_subtitle.printf (GLib.format_size (recommended_resources.ram,
                                                                         GLib.FormatSizeFlags.IEC_UNITS)));
            if (machine.storage_volume != null)
                storage_row.set_subtitle (row_subtitle.printf (GLib.format_size (recommended_resources.storage,
                                                                                 GLib.FormatSizeFlags.IEC_UNITS)));
        }
    }

    private void setup_cpu_row () {
        try {
            var host_topology = machine.connection.get_node_info ();
            uint host_vcpus = host_topology.cores * host_topology.sockets * host_topology.threads;
            uint64 cpus = machine.domain_config.get_vcpus ();

            cpus_spin_button.set_range (1, host_vcpus);
            cpus_spin_button.set_increments (1, host_vcpus);
            cpus_spin_button.set_value (cpus);
        } catch (GLib.Error error) {
            warning ("Failed to obtain virtual resources for machine: %s", error.message);
        }

        cpus_spin_button.value_changed.connect (on_cpu_spin_button_changed);
    }

    private void on_cpu_spin_button_changed () {
        uint cores = cpus_spin_button.get_value_as_int ();

        try {
            if (machine.domain_config.get_vcpus () == cores)
                return;

            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            config.set_vcpus (cores);
            if (config.get_class ().find_property ("current-vcpus") != null)
                config.set ("current-vcpus", cores);

            /* TODO: research for a decent rationalization for the values below. */
            var guest_topology = new GVirConfig.CapabilitiesCpuTopology ();
            guest_topology.set_cores (cores);
            guest_topology.set_sockets (1);
            guest_topology.set_threads (1);

            var cpu = machine.domain_config.get_cpu ();
            cpu.set_topology (guest_topology);
            config.set_cpu (cpu);

            machine.domain.set_config (config);
            debug ("vCPUS changed to %u", cores);

            // TODO: If machine ON -> Restart!
        } catch (GLib.Error error) {
            debug ("Failed to set the number of vCPUS for '%s': %s", machine.name, error.message);
        }
    }

    [GtkCallback]
    private async void on_run_in_bg_toggled () {
        if (!machine.run_in_bg)
            return;

        if (!App.is_running_in_flatpak ())
            return;

        if (!run_in_bg_toggle.get_active ())
            return;

        try {
            var portal = new Xdp.Portal.initable_new ();
            var window = App.app.main_window;
            var parent = Xdp.parent_new_gtk (window);
            var reason = _("Boxes wants to run VM in background");
            var cancellable = null;
            yield portal.request_background (parent, reason, new GLib.GenericArray<weak string>(), NONE, cancellable);
        } catch (GLib.Error error) {
            warning ("Failed to request to run in background: %s", error.message);
            machine.run_in_bg = false;

            var msg = _("Boxes is not authorized to run in background");
            var message_dialog = new Gtk.MessageDialog (App.app.main_window,
                                                        Gtk.DialogFlags.MODAL,
                                                        Gtk.MessageType.QUESTION,
                                                        Gtk.ButtonsType.YES_NO,
                                                        msg);
            message_dialog.format_secondary_text (_("Do you want to open Settings to manage application permissions?"));
            message_dialog.show_all ();
            message_dialog.response.connect ((dialog, response) => {
                if (response == Gtk.ResponseType.YES)
                    open_permission_settings ();

                message_dialog.destroy ();
            });
        }
    }

    [GtkCallback]
    public void show_logs () {
        if (logs == null)
            logs = collect_logs (machine);
        
        try {
            var filename = get_cache ("logs", machine.domain.get_name () + ".logs");
            File file = GLib.File.new_for_path (filename);

            FileOutputStream os = file.replace (null, false, FileCreateFlags.REPLACE_DESTINATION);

            os.write (logs.data);
            GLib.AppInfo.launch_default_for_uri (file.get_uri (), null);

            debug ("Showing vm configuration at %s", file.get_uri ());
            GLib.stdout.printf (logs + "\n");
        } catch (GLib.Error error) {
            warning ("Failed to collect machine logs: %s", error.message);
        }
    }

    [GtkCallback]
    private async void on_edit_configuration_button_clicked () {
        var message_dialog = new Gtk.MessageDialog (get_toplevel () as Gtk.Window,
                                                    Gtk.DialogFlags.MODAL,
                                                    Gtk.MessageType.QUESTION,
                                                    Gtk.ButtonsType.YES_NO,
                                                    _("Editing your box configuration can cause issues to the operating system of your box. Would you like to create a snapshot to recover from your changes?"));
        message_dialog.show_all ();
        message_dialog.response.connect (create_snapshot); 
    }

    private async void create_snapshot (Gtk.Dialog message_dialog, int response) {
        if (response == Gtk.ResponseType.YES) {
            debug ("Creating snapshot...");

            try {
                // TODO: create a better snapshot description label.
                yield machine.create_snapshot ();
            } catch (GLib.Error error) {
                warning ("Failed to create snapshot: %s", error.message);
            }
        }

        message_dialog.destroy ();
        open_config_file ();
    }

    private void open_config_file () {
        try {
            var domain_xml = machine.domain_config.to_xml ();
            File file = GLib.File.new_for_path (Path.build_filename (Environment.get_home_dir (),
                                                "." + machine.domain.get_name () + ".draft.txt"));
            FileOutputStream os = file.replace (null, false, FileCreateFlags.REPLACE_DESTINATION);
            os.write (domain_xml.data);

            config_file_monitor = file.monitor_file (GLib.FileMonitorFlags.NONE, null);
            config_file_monitor.changed.connect (on_domain_configuration_edited);

            GLib.AppInfo.launch_default_for_uri (file.get_uri (), null);
        } catch (GLib.Error error) {
            warning ("Failed to edit VM configuration: %s", error.message);
        }
    }

    private void on_domain_configuration_edited (File file,
                                                 File? other_file,
                                                 FileMonitorEvent event_type) {
        if (event_type != FileMonitorEvent.CHANGES_DONE_HINT) {
            return;
        }

        try {
            uint8[] contents;
            string etag_out;
            file.load_contents (null, out contents, out etag_out);

            GVirConfig.Domain new_config = new GVirConfig.Domain.from_xml ((string)contents);
            var edited_tag = "<edited>%s</edited>".printf (new DateTime.now_local ().to_string ());
            new_config.set_custom_xml (edited_tag,
                                       "edited",
                                       "https://wiki.gnome.org/Apps/Boxes/edited");
            machine.domain.set_config (new_config);

            debug ("Overriding configuration for %s", machine.domain.get_name ());
        } catch (GLib.Error error) {
            warning ("Failed to load new domain configuration: %s", error.message);

            var message_dialog = new Gtk.MessageDialog (App.app.main_window,
                                                        Gtk.DialogFlags.MODAL,
                                                        Gtk.MessageType.ERROR,
                                                        Gtk.ButtonsType.CLOSE,
                                                        _("Failed to save domain configuration: %s"),
                                                        error.message);
            message_dialog.run ();
            message_dialog.destroy ();
        }
    }

    private void on_machine_state_changed () {
        if (machine.is_running) {
            resources_group.description = _("Changes to the settings below take effect after you restart your box.");
        } else {
            resources_group.description = null;
        }
    }

    private void bind_widget_property (Gtk.Widget widget, string widget_property, string machine_property) {
        machine.bind_property (machine_property, widget, widget_property, BindingFlags.BIDIRECTIONAL);

        var value = GLib.Value (machine.get_class ().find_property (machine_property).value_type);
        machine.get_property (machine_property, ref value);
        widget.set_property (widget_property, value);
    }

    private string collect_logs (LibvirtMachine machine) {
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
}
