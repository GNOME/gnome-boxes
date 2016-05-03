// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.LibvirtClonedMedia : Boxes.LibvirtMedia  {
    public LibvirtClonedMedia (string path, GVirConfig.Domain domain_config) throws GLib.Error {
        base (path, domain_config, true);
    }

    public override VMCreator get_vm_creator () {
        return new LibvirtVMCloner (this);
    }
}
