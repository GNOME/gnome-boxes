// This file is part of GNOME Boxes. License: LGPLv2+

using Osinfo;
using GVir;

private class Boxes.VMCreator {
    private Connection connection;

    public VMCreator (string uri) throws GLib.Error {
        connection = new Connection (uri);
    }

    public async GVir.Domain create_domain_for_installer (InstallerMedia install_media,
                                                          Resources      resources,
                                                          Cancellable?   cancellable) throws GLib.Error {
        if (!connection.is_open ())
            yield connect (cancellable);

        if (install_media is UnattendedInstaller)
            yield (install_media as UnattendedInstaller).setup (cancellable);

        string name;
        if (install_media.os != null)
            name = install_media.os.name;
        else
            name = install_media.label;

        var target_path = yield create_target_volume (name, resources.storage);

        var xml = get_virt_xml (install_media, name, target_path, resources);
        var config = new GVirConfig.Domain.from_xml (xml);

        return connection.create_domain (config);
    }

    private async void connect (Cancellable? cancellable) throws GLib.Error {
        yield connection.open_async (cancellable);
        yield connection.fetch_domains_async (cancellable);
        yield connection.fetch_storage_pools_async (cancellable);
    }

    private string get_virt_xml (InstallerMedia install_media, string name, string target_path, Resources resources) {
        // FIXME: This information should come from libosinfo
        var clock_offset = "utc";
        if (install_media.os != null && install_media.os.short_id.contains ("win"))
            clock_offset = "localtime";

        var domain_name = name;
        for (var i = 1; connection.find_domain_by_name (domain_name) != null; i++)
            domain_name = name + "-" + i.to_string ();

        var ram = (resources.ram / KIBIBYTES).to_string ();
        return "<domain type='kvm'>\n" +
               "  <name>" +  domain_name + "</name>\n" +
               "  <memory>" + ram + "</memory>\n" +
               "  <vcpu>" + resources.n_cpus.to_string () + "</vcpu>\n" +
               "  <os>\n" +
               "    <type arch='x86_64'>hvm</type>\n" +
               "    <boot dev='cdrom'/>\n" +
               "    <boot dev='hd'/>\n" +
               get_direct_boot_xml (install_media) +
               "  </os>\n" +
               "  <features>\n" +
               "    <acpi/><apic/><pae/>\n" +
               "  </features>\n" +
               "  <clock offset='" + clock_offset + "'/>\n" +
               "  <on_poweroff>destroy</on_poweroff>\n" +
               "  <on_reboot>destroy</on_reboot>\n" +
               "  <on_crash>destroy</on_crash>\n" +
               "  <devices>\n" +
               "    <disk type='file' device='disk'>\n" +
               "      <driver name='qemu' type='qcow2'/>\n" +
               "      <source file='" + target_path + "'/>\n" +
               "      <target dev='hda' bus='ide'/>\n" +
               "    </disk>\n" +
               get_unattended_dir_floppy_xml (install_media) +
               get_source_media_xml (install_media) +
               "    <interface type='user'>\n" +
               "      <mac address='00:11:22:33:44:55'/>\n" +
               "    </interface>\n" +
               "    <input type='tablet' bus='usb'/>\n" +
               "    <graphics type='spice'/>\n" +
               "    <console type='pty'/>\n" +
               "    <video>\n" +
               // FIXME: Should be 'qxl', work-around for a spice bug
               "      <model type='vga'/>\n" +
               "    </video>\n" +
               "  </devices>\n" +
               "</domain>";
    }

    private async string create_target_volume (string name, int64 storage) throws GLib.Error {
        var pool = yield get_storage_pool ();

        var volume_name = name + ".qcow2";
        for (var i = 1; pool.get_volume (volume_name) != null; i++)
            volume_name = name + "-" + i.to_string () + ".qcow2";

        var storage_str = (storage / GIBIBYTES).to_string ();
        var xml = "<volume>\n" +
                  "  <name>" + volume_name + "</name>\n" +
                  "  <capacity unit='G'>" + storage_str + "</capacity>\n" +
                  "  <target>\n" +
                  "    <format type='qcow2'/>\n" +
                  "    <permissions>\n" +
                  "      <owner>" + get_uid () + "</owner>\n" +
                  "      <group>" + get_gid () + "</group>\n" +
                  "      <mode>0744</mode>\n" +
                  "      <label>virt-image-" + name + "</label>\n" +
                  "    </permissions>\n" +
                  "  </target>\n" +
                  "</volume>";
        var config = new GVirConfig.StorageVol.from_xml (xml);
        var volume = pool.create_volume (config);

        return volume.get_path ();
    }

    private string get_source_media_xml (InstallerMedia install_media) {
        string type, source_attr;

        if (install_media.from_image) {
            type = "file";
            source_attr = "file" ;
        } else {
            type = "block";
            source_attr = "dev";
        }

        return "    <disk type='" + type + "'\n" +
               "          device='cdrom'>\n" +
               "      <driver name='qemu' type='raw'/>\n" +
               "      <source " + source_attr + "='" +
                                  install_media.device_file + "'/>\n" +
               "      <target dev='hdc' bus='ide'/>\n" +
               "      <readonly/>\n" +
               "    </disk>\n";
    }

    private string get_unattended_dir_floppy_xml (InstallerMedia install_media) {
        if (!(install_media is UnattendedInstaller))
            return "";

        var floppy_path = (install_media as UnattendedInstaller).floppy_path;
        if (floppy_path == null)
            return "";

        return "    <disk type='file' device='floppy'>\n" +
               "      <driver name='qemu' type='raw'/>\n" +
               "      <source file='" + floppy_path + "'/>\n" +
               "      <target dev='fd'/>\n" +
               "    </disk>\n";
    }

    private string get_direct_boot_xml (InstallerMedia install_media) {
        if (!(install_media is UnattendedInstaller))
            return "";

        var unattended = install_media as UnattendedInstaller;

        var kernel_path = unattended.kernel_path;
        var initrd_path = unattended.initrd_path;

        if (kernel_path == null || initrd_path == null)
            return "";

        return "    <kernel>" + kernel_path + "</kernel>\n" +
               "    <initrd>" + initrd_path + "</initrd>\n" +
               "    <cmdline>ks=floppy</cmdline>\n";
    }

    private async StoragePool get_storage_pool () throws GLib.Error {
        var pool = connection.find_storage_pool_by_name (Config.PACKAGE_TARNAME);
        if (pool == null) {
            var pool_path = get_pkgconfig ("images");
            var xml = "<pool type='dir'>\n" +
                      "<name>" + Config.PACKAGE_TARNAME + "</name>\n" +
                      "  <source>\n" +
                      "    <directory path='" + pool_path + "'/>\n" +
                      "  </source>\n" +
                      "  <target>\n" +
                      "    <path>" + pool_path + "</path>\n" +
                      "    <permissions>\n" +
                      "      <owner>" + get_uid () + "</owner>\n" +
                      "      <group>" + get_gid () + "</group>\n" +
                      "      <mode>0744</mode>\n" +
                      "      <label>" + Config.PACKAGE_TARNAME + "</label>\n" +
                      "    </permissions>\n" +
                      "  </target>\n" +
                      "</pool>";
            var config = new GVirConfig.StoragePool.from_xml (xml);
            pool = connection.create_storage_pool (config, 0);
            yield pool.build_async (0, null);
            yield pool.start_async (0, null);
        }

        // This should be async
        pool.refresh (null);

        return pool;
    }

    private string get_uid () {
        return ((uint32) Posix.getuid ()).to_string ();
    }

    private string get_gid () {
        return ((uint32) Posix.getgid ()).to_string ();
    }
}
