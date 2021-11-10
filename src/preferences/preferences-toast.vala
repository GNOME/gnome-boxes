// This file is part of GNOME Boxes. License: LGPLv2+

[GtkTemplate (ui = "/org/gnome/Boxes/ui/preferences/preferences-toast.ui")]
private class Boxes.PreferencesToast : Gtk.Box {
    public delegate void OKFunc ();
    public delegate void DismissFunc ();

    [GtkChild]
    private unowned Gtk.Label label;
    [GtkChild]
    private unowned Gtk.Button button;

    public string message {
        set {
            label.label = value;
        }
        get {
            return label.label;
        }
    }

    public string action {
        set {
            button.label = value; 
        }
        get {
            return button.label;
        }
    }

    public OKFunc? undo_func;
    public DismissFunc? dismiss_func;

    public void dismiss () {
        if (dismiss_func != null)
            dismiss_func ();

        destroy ();
    }

    [GtkCallback]
    private void on_dismiss_button_clicked () {
        dismiss ();
    }

    [GtkCallback]
    private void on_undo_button_clicked () {
        if (undo_func != null)
            undo_func ();

        destroy ();
    }
}
