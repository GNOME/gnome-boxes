// This file is part of GNOME Boxes. License: LGPLv2+

namespace org.freedesktop.portal {
    [DBus(name = "org.freedesktop.portal.Request")]
    public interface Request : GLib.Object {
        [DBus(name = "Close")]
        public abstract void close () throws DBusError, IOError;

        [DBus(name = "Response")]
        public signal void response (uint response, GLib.HashTable<string, GLib.Variant> results);
    }

    [DBus(name = "org.freedesktop.portal.Background")]
    public interface Background : GLib.Object {
        [DBus(name = "RequestBackground")]
        public abstract GLib.ObjectPath request_background (string parent_window, GLib.HashTable<string, GLib.Variant> options) throws DBusError, IOError;
    }
}

private class Boxes.Portals : GLib.Object {
    private static Portals portals;
    public static Portals get_default () {
        if (portals == null)
            portals = new Portals ();

        return portals;
    }

    private const string BUS_NAME = "org.freedesktop.portal.Desktop";
    private const string OBJECT_PATH = "/org/freedesktop/portal/desktop";

    public delegate void PortalRequestCallback (uint response, GLib.HashTable<string, GLib.Variant>? results = null);

    private GLib.DBusConnection bus;

    public async void request_to_run_in_background (owned PortalRequestCallback? callback = null) {
        try {
            debug ("Requesting to run in background");

            if (bus == null)
                bus = yield Bus.get(BusType.SESSION);

            var background = yield bus.get_proxy<org.freedesktop.portal.Background>(BUS_NAME, OBJECT_PATH);
            var options = new GLib.HashTable<string, GLib.Variant>(str_hash, str_equal);
            options.insert ("reason", new GLib.Variant ("s", _("Boxes wants to run VM in background")));
            var handle = background.request_background (Config.APPLICATION_ID, options);

            var request = yield bus.get_proxy<org.freedesktop.portal.Request>(BUS_NAME, handle);
            request.response.connect ((response, results) => {
                debug ("Received request response from portal");

                callback (response, null);
            });

            yield;
        } catch (GLib.Error error) {
            warning ("Failed to request to run in background: %s", error.message);
        }
    }
}
