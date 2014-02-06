// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/notification.ui")]
private class Boxes.Notification: Gd.Notification {
    public const int DEFAULT_TIMEOUT = 6;

    public delegate void OKFunc ();
    public delegate void CancelFunc ();

    [GtkChild]
    private Gtk.Label message_label;
    [GtkChild]
    private Gtk.Label ok_button_label;
    [GtkChild]
    private Gtk.Button ok_button;

    public Notification (string            message,
                         MessageType       message_type,
                         string?           ok_label,
                         owned OKFunc?     ok_func,
                         owned CancelFunc? cancel_func,
                         int               timeout) {
        this.timeout = timeout;

        bool ok_pressed = false;
        dismissed.connect ( () => {
            if (!ok_pressed && cancel_func != null)
                cancel_func ();
        });

        message_label.label = message;

        if (ok_label != null) {
            ok_button_label.label = ok_label;

            ok_button.clicked.connect ( () => {
                ok_pressed = true;
                if (ok_func != null)
                    ok_func ();
                dismiss ();
            });

            ok_button.show_all ();
        }
    }
}
