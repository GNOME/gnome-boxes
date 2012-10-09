[CCode (cprefix = "GVir", gir_namespace = "LibvirtGObject", gir_version = "1.0", lower_case_cprefix = "gvir_")]
namespace BoxesGVir {
	[CCode (cheader_filename = "libvirt-gobject/libvirt-gobject.h", type_id = "gvir_domain_get_type ()")]
	public class Domain : GLib.Object {
		public async bool wakeup_async (uint flags, GLib.Cancellable? cancellable) throws GLib.Error;
	}
}

[CCode (cprefix = "GVirConfig", gir_namespace = "LibvirtGConfig", gir_version = "1.0", lower_case_cprefix = "gvir_config_")]
namespace BoxesGVirConfig {
	[CCode (cheader_filename = "libvirt-gconfig/libvirt-gconfig.h", type_id = "gvir_config_domain_get_type ()")]
	public class Domain : GVirConfig.Object {
		public void set_power_management (BoxesGVirConfig.DomainPowerManagement? pm);
	}
	[CCode (cheader_filename = "libvirt-gconfig/libvirt-gconfig.h", type_id = "gvir_config_domain_power_management_get_type ()")]
	public class DomainPowerManagement : GVirConfig.Object {
		[CCode (has_construct_function = false)]
		public DomainPowerManagement ();
		public void set_disk_suspend_enabled (bool enabled);
		public void set_mem_suspend_enabled (bool enabled);
	}
}
