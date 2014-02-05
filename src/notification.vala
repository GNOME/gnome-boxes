// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private class Boxes.Notification: Gd.Notification {
    public const int DEFAULT_TIMEOUT = 6;

    public delegate void OKFunc ();
    public delegate void CancelFunc ();

    public Notification (string            message,
                         MessageType       message_type,
                         string?           ok_label,
                         owned OKFunc?     ok_func,
                         owned CancelFunc? cancel_func,
                         int               timeout) {
        valign = Gtk.Align.START;
        this.timeout = timeout;

        bool ok_pressed = false;
        dismissed.connect ( () => {
            if (!ok_pressed && cancel_func != null)
                cancel_func ();
        });

        var grid = new Gtk.Grid ();
        grid.set_orientation (Gtk.Orientation.HORIZONTAL);
        grid.margin_left = 12;
        grid.margin_right = 12;
        grid.column_spacing = 12;
        grid.valign = Gtk.Align.CENTER;
        add (grid);

        var message_label = new Label (message);
        grid.add (message_label);

        if (ok_label != null) {
            var ok_button = new Button.with_mnemonic (ok_label);
            ok_button.halign = Gtk.Align.END;
            grid.add (ok_button);

            ok_button.clicked.connect ( () => {
                ok_pressed = true;
                if (ok_func != null)
                    ok_func ();
                dismiss ();
            });
        }

        show_all ();
    }
}
