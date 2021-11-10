// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.RamRow : Boxes.MemoryRow {
    private LibvirtMachine machine;

    public void setup (LibvirtMachine machine) {
        this.machine = machine;

        try {
            var host_topology = machine.connection.get_node_info ();

            var available_ram = host_topology.memory;
            uint64 ram = machine.domain_config.memory * Osinfo.KIBIBYTES;
            uint64 max_ram = available_ram * Osinfo.KIBIBYTES; 
            uint64 min_ram = 64 * Osinfo.MEBIBYTES;

            spin_button.set_range (min_ram, max_ram);
            spin_button.set_increments (min_ram, max_ram);
            spin_button.set_value (ram);
        } catch (GLib.Error error) {
            warning ("Failed to obtain virtual resources for '%s', %s",
                     machine.name,
                     error.message);
        }

        spin_button.value_changed.connect (on_spin_button_changed);
    }

    [GtkCallback]
    private void on_spin_button_changed () {
        uint64 ram = (uint64)spin_button.get_value () / Osinfo.KIBIBYTES;

        try {
            var config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            config.memory = ram;

            if (config.get_class ().find_property ("current-memory") != null)
                config.set ("current-memory", ram);

            machine.domain.set_config (config);
            debug ("RAM changed to %llu KiB", ram);
        } catch (GLib.Error error) {
            warning ("Failed to change RAM of box '%s' to %llu KiB: %s",
                     machine.name, ram, error.message);
        }
    }
}
