// This file is part of GNOME Boxes. License: LGPLv2+
using GVir;
using Gtk;

private class Boxes.LibvirtBroker : Boxes.Broker {
    private static LibvirtBroker broker;
    private HashTable<string,GVir.Connection> connections;

    public static LibvirtBroker get_default () {
        if (broker == null)
            broker = new LibvirtBroker ();

        return broker;
    }

    private LibvirtBroker () {
        connections = new HashTable<string, GVir.Connection> (str_hash, str_equal);
    }

    public GVir.Connection get_connection (string name) {
        return_if_fail (broker != null);
        return broker.connections.get (name);
    }

    public LibvirtMachine add_domain (CollectionSource source, GVir.Connection connection, GVir.Domain domain)
                                      throws GLib.Error {
        return_if_fail (broker != null);

        var machine = domain.get_data<LibvirtMachine> ("machine");
        if (machine != null)
            return machine; // Already added

        machine = new LibvirtMachine (source, connection, domain);
        machine.suspend_at_exit = (connection == App.app.default_connection);
        App.app.collection.add_item (machine);
        domain.set_data<LibvirtMachine> ("machine", machine);

        return machine;
    }

    // New == Added after Boxes launch
    private void try_add_new_domain (CollectionSource source, GVir.Connection connection, GVir.Domain domain) {
        try {
            add_domain (source, connection, domain);
        } catch (GLib.Error error) {
            warning ("Failed to create source '%s': %s", source.name, error.message);
        }
    }

    // Existing == Existed before Boxes was launched
    private void try_add_existing_domain (CollectionSource source, GVir.Connection connection, GVir.Domain domain) {
        try {
            var machine = add_domain (source, connection, domain);
            var config = machine.domain_config;

            if (VMConfigurator.is_install_config (config) || VMConfigurator.is_live_config (config)) {
                debug ("Continuing installation/live session for '%s', ..", machine.name);
                new VMCreator.for_install_completion (machine); // This instance will take care of its own lifecycle
            }
        } catch (GLib.Error error) {
            warning ("Failed to create source '%s': %s", source.name, error.message);
        }
    }

    public override async void add_source (CollectionSource source) {
        if (connections.lookup (source.name) != null)
            return;

        var connection = new GVir.Connection (source.uri);

        try {
            yield connection.open_async (null);
            yield connection.fetch_domains_async (null);
            yield connection.fetch_storage_pools_async (null);
            var pool = Boxes.get_storage_pool (connection);
            if (pool != null) {
                if (pool.get_info ().state == GVir.StoragePoolState.INACTIVE)
                    yield pool.start_async (0, null);
                // If default storage pool exists, we should refresh it already
                yield pool.refresh_async (null);
            }
        } catch (GLib.Error error) {
            warning (error.message);
        }

        connections.insert (source.name, connection);

        foreach (var domain in connection.get_domains ())
            try_add_existing_domain (source, connection, domain);

        connection.domain_removed.connect ((connection, domain) => {
            var machine = domain.get_data<LibvirtMachine> ("machine");
            if (machine == null)
                return; // Looks like we removed the domain ourselves. Nothing to do then..

            App.app.delete_machine (machine, false);
        });

        connection.domain_added.connect ((connection, domain) => {
            debug ("New domain '%s'", domain.get_name ());
            try_add_new_domain (source, connection, domain);
        });
    }
}

