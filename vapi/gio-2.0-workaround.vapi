// Workaround non-working GLib.g_io_error_from_errno
[CCode (cheader_filename = "gio/gio.h")]
public const int G_IO_ERROR;

[CCode (cheader_filename = "gio/gio.h")]
public int g_io_error_from_errno (int err_no);
