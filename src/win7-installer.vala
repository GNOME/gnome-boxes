// This file is part of GNOME Boxes. License: LGPLv2+

using GVirConfig;

// Automated installer media for Windows 7 and 2008

private class Boxes.Win7Installer: WindowsInstaller {
    private static Regex arch_regex;

    public override uint64 installed_size {
        get {
            return express_install? 7554351104 : 0;
        }
    }

    public override bool supports_virtio_disk {
        get {
            return (extra_iso != null);
        }
    }

    static construct {
        try {
            arch_regex = new Regex ("BOXES_CPU");
        } catch (RegexError error) {
            // This just can't fail
            assert_not_reached ();
        }
    }

    protected override string fill_unattended_data (string data) throws RegexError {
        var str = base.fill_unattended_data (data);

        switch (os_media.architecture) {
            case "x86_64":
                return arch_regex.replace (str, str.length, 0, "amd64");

            case "i386":
                return arch_regex.replace (str, str.length, 0, "x86");

            default:
                warning ("Unexpected osinfo win7 arch: %s", os_media.architecture);

                return arch_regex.replace (str, str.length, 0, "x86");
        }
    }

    public Win7Installer.from_media (InstallerMedia media) throws GLib.Error {
        var unattended_source = get_unattended (media.os.short_id + ".xml");
        base.from_media (media, unattended_source, "Autounattend.xml");

        newline_type = DataStreamNewlineType.CR_LF;

        lang = lang.replace ("_", "-");
        // Remove '.' and everything after it
        lang = /\..*/i.replace (lang, -1, 0, "");

        if (os != null && os.short_id.length > 15)
            critical ("'%s' is longer than 15 characters, expect %s express installation to fail!",
                      os.short_id,
                      os.name);
        extra_iso = "win-tools.iso";
    }
}
