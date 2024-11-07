// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;
using Gtk;

private class Boxes.LibvirtBroker : Boxes.Broker {
    private static LibvirtBroker broker;
    private HashTable<string,GVir.Connection> connections;
    private GLib.List<GVir.Domain> pending_domains;

    public static LibvirtBroker get_default () {
        if (broker == null)
            broker = new LibvirtBroker ();

        return broker;
    }

    private LibvirtBroker () {
        connections = new HashTable<string, GVir.Connection> (str_hash, str_equal);
        pending_domains = new GLib.List<GVir.Domain> ();
    }

    public GVir.Connection get_connection (string name) {
        return connections.get (name);
    }

    public async LibvirtMachine? add_domain (CollectionSource source, GVir.Connection connection, GVir.Domain domain)
                                             throws GLib.Error {
        if (pending_domains.find (domain) != null) {
            // Already being added asychronously
            SourceFunc callback = add_domain.callback;
            ulong id = 0;
            id = App.app.collection.item_added.connect ((item) => {
                if (!(item is LibvirtMachine))
                    return;

                var libvirt_machine = item as LibvirtMachine;
                if (libvirt_machine.domain != domain)
                    return;

                App.app.collection.disconnect (id);
                callback ();
            });

            yield;
        }

        var machine = domain.get_data<LibvirtMachine> ("machine");
        if (machine != null)
            return machine; // Already added

        pending_domains.append (domain);
        machine = yield new LibvirtMachine (source, connection, domain);
        pending_domains.remove (domain);

        domain.set_data<LibvirtMachine> ("machine", machine);
        App.app.collection.add_item (machine);

        if (source.name != App.DEFAULT_SOURCE_NAME)
            return machine;


        try {
            var config = machine.domain.get_config (0);
            yield VMConfigurator.update_existing_domain (config, connection);
            machine.domain.set_config (config);

            /* FIXME: reload local properties to sync with libvirt domain xml
               since DomainGraphicsSpice doesn't have a get_gl method, we need to store
               and reload that setting ourselves.
            */
            machine.acceleration_3d = !!machine.acceleration_3d;
            machine.run_in_bg = !!machine.run_in_bg;
        } catch (GLib.Error e) {
            warning ("Failed to update domain '%s': %s", domain.get_name (), e.message);
        }

        return machine;
    }

    // New == Added after Boxes launch
    private async void try_add_new_domain (CollectionSource source, GVir.Connection connection, GVir.Domain domain) {
        if (domain.get_name ().has_prefix ("guestfs-")) {
            debug ("Ignoring guestfs domain '%s'", domain.get_name ());

            return;
        }

        try {
            yield add_domain (source, connection, domain);
        } catch (GLib.Error error) {
            warning ("Failed to create source '%s': %s", source.name, error.message);
        }
    }

    // Existing == Existed before Boxes was launched
    private async LibvirtMachine? try_add_existing_domain (CollectionSource source,
                                                           GVir.Connection  connection,
                                                           GVir.Domain      domain) {
        try {
            var machine = yield add_domain (source, connection, domain);
            var config = machine.domain_config;

            if (VMConfigurator.is_import_config (config)) {
                debug ("Continuing import of '%s', ..", machine.name);
                new VMImporter.for_import_completion (machine);
            } else if (VMConfigurator.is_libvirt_system_import_config (config)) {
                debug ("Continuing import of '%s', ..", machine.name);
                new LibvirtVMImporter.for_import_completion (machine);
            } else if (VMConfigurator.is_libvirt_cloning_config (config)) {
                debug ("Continuing cloning of '%s', ..", machine.name);
                new LibvirtVMCloner.for_cloning_completion (machine);
            }

            return machine;
        } catch (GLib.Error error) {
            warning ("Failed to create source '%s': %s", source.name, error.message);

            return null;
        }
    }

    public override async void add_source (CollectionSource source) throws GLib.Error {
        if (connections.lookup (source.name) != null)
            return;

        var connection = new GVir.Connection (source.uri);

        yield connection.open_async (null);
        yield connection.fetch_domains_async (null);
        yield connection.fetch_storage_pools_async (null);
        yield Boxes.ensure_storage_pool (connection);

        connections.insert (source.name, connection);

        var clones = new GLib.List<LibvirtMachine> ();
        foreach (var domain in connection.get_domains ()) {
            var machine = yield try_add_existing_domain (source, connection, domain);

            if (VMConfigurator.is_libvirt_cloning_config (machine.domain_config))
                clones.append (machine);
        }

        foreach (var clone in clones) {
            var vm_importer = clone.vm_creator as VMImporter;

            if (vm_importer == null) {
                warning ("Failed to find creater of clone '%s'", clone.name);

                continue;
            }
            var disk_path = vm_importer.source_media.device_file;
            LibvirtMachine? cloned = null;

            for (int i = 0 ; i < App.app.collection.length ; i++) {
                var item = App.app.collection.get_item (i);

                if (!(item is LibvirtMachine))
                    continue;

                var machine = item as LibvirtMachine;
                var volume = machine.storage_volume;
                if (volume != null && volume.get_path () == disk_path) {
                    cloned = machine;

                    break;
                }
            }

            if (cloned == null) {
                warning ("Failed to find source machine of clone %s", clone.name);

                continue;
            }

            cloned.can_delete = false;
            ulong under_construct_id = 0;
            under_construct_id = clone.notify["under-construction"].connect (() => {
                if (!clone.under_construction) {
                    cloned.can_delete = true;
                    clone.disconnect (under_construct_id);
                }
            });
        }

        connection.domain_removed.connect ((connection, domain) => {
            var machine = domain.get_data<LibvirtMachine> ("machine");
            if (machine == null)
                return; // Looks like we removed the domain ourselves. Nothing to do then..

            App.app.delete_machine (machine, false);
        });

        connection.domain_added.connect ((connection, domain) => {
            debug ("New domain '%s'", domain.get_name ());
            try_add_new_domain.begin (source, connection, domain);
        });

        yield base.add_source (source);
    }
}

