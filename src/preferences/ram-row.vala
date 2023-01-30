// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.RamRow : Boxes.MemoryRow {
    construct {
        try {
            var host_topology = App.app.default_connection.get_node_info ();

            var available_ram = host_topology.memory;
            uint64 max_ram = available_ram * Osinfo.KIBIBYTES; 
            uint64 min_ram = 64 * Osinfo.MEBIBYTES;

            spin_button.set_range (min_ram, max_ram);
            spin_button.set_increments (min_ram, max_ram);
        } catch (GLib.Error error) {
            warning ("Failed to obtain virtual resources %s",
                     error.message);
        }
    }
}
