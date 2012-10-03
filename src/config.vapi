[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "config.h")]
namespace Config {
        [CCode (cheader_filename = "version.h")]
        public const string BUILD_VERSION;
        public const string PACKAGE_DATADIR;
        public const string PACKAGE_TARNAME;
        public const string GETTEXT_PACKAGE;
        public const string GNOMELOCALEDIR;
        public const string DATADIR;
        public const string PACKAGE_BUGREPORT;
        public const string PACKAGE_URL;
        public const bool HAVE_WAKEUP;
}
