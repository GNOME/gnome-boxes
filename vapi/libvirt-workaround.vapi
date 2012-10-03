[CCode (cprefix = "GVir", gir_namespace = "LibvirtGObject", gir_version = "1.0", lower_case_cprefix = "gvir_")]
namespace BoxesGVir {
	[CCode (cheader_filename = "libvirt-gobject/libvirt-gobject.h", type_id = "gvir_domain_get_type ()")]
	public class Domain : GLib.Object {
		public async bool wakeup_async (uint flags, GLib.Cancellable? cancellable) throws GLib.Error;
	}
}
