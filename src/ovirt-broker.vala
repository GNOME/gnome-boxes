// This file is part of GNOME Boxes. License: LGPLv2+
using Ovirt;

private class Boxes.OvirtBroker : Boxes.Broker {
    private static OvirtBroker broker;
    private HashTable<string,Ovirt.Proxy> proxies;

    public static OvirtBroker get_default () {
        if (broker == null)
            broker = new OvirtBroker ();

        return broker;
    }

    private OvirtBroker () {
        proxies = new HashTable<string, Ovirt.Proxy> (str_hash, str_equal);
    }

   private void add_vm (CollectionSource source, Ovirt.Proxy proxy, Ovirt.Vm vm) {
        try {
            var machine = new OvirtMachine (source, proxy, vm);
            App.app.collection.add_item (machine);
        } catch (GLib.Error error) {
            warning ("Failed to create source '%s': %s", source.name, error.message);
        }
    }

    public override async void add_source (CollectionSource source) {
        if (proxies.lookup (source.name) != null)
            return;

        // turn ovirt://host/path into https://host/path/api which
        // is where the REST API is reachable from
        Xml.URI uri = Xml.URI.parse (source.uri);
        return_if_fail (uri.scheme == "ovirt");
        uri.scheme = "https";
        if (uri.path == null)
            uri.path= "/api";
        else
            uri.path = GLib.Path.build_filename (uri.path, "api");

        var proxy = new Ovirt.Proxy (uri.save ());

        try {
            yield proxy.fetch_ca_certificate_async (null);
            yield proxy.fetch_vms_async (null);
        } catch (GLib.Error error) {
            debug ("Failed to connect to broker: %s", error.message);
            App.app.notificationbar.display_error (_("Connection to oVirt broker failed"));
        }
        proxies.insert (source.name, proxy);

        foreach (var vm in proxy.get_vms ()) {
            add_vm (source, proxy, vm);
        }
    }
}
