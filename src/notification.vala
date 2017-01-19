// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/notification.ui")]
private class Boxes.Notification: Gtk.Revealer {
    public signal void dismissed ();

    public const int DEFAULT_TIMEOUT = 6;
    private int timeout = DEFAULT_TIMEOUT;

    public delegate void OKFunc ();
    public delegate void DismissFunc ();

    [GtkChild]
    private Gtk.Label message_label;
    [GtkChild]
    private Gtk.Label ok_button_label;
    [GtkChild]
    private Gtk.Button ok_button;
    [GtkChild]
    private Gtk.Button close_button;

    public Notification (string             message,
                         MessageType        message_type,
                         string?            ok_label,
                         owned OKFunc?      ok_func,
                         owned DismissFunc? dismiss_func,
                         int                timeout) {
        /*
         * Templates cannot set construct properties, so
         * lets use the respective property setter method.
         */
        set_reveal_child (true);

        this.timeout = timeout;
        Timeout.add_seconds (this.timeout, () => {
            dismiss ();

            return true;
        });

        bool ok_pressed = false;
        dismissed.connect ( () => {
            if (!ok_pressed && dismiss_func != null)
                dismiss_func ();
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

        close_button.clicked.connect (dismiss);
    }

    public void dismiss () {
        set_reveal_child (false);
        dismissed ();
    }
}
