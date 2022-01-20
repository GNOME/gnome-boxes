// This file is part of GNOME Boxes. License: LGPLv2+

private class Boxes.ToastOverlay : Gtk.Overlay {
    private Boxes.Toast _toast;
    private Boxes.Toast toast {
        set {
            if (_toast != null) {
                _toast.dismiss ();
            }

            _toast = value;
            add_overlay (_toast);
        }

        get {
            return _toast;
        }
    }

    public void display_toast (Boxes.Toast toast) {
        this.toast = toast;
    }

    public void dismiss () {
        if (toast != null) {
            toast.dismiss ();
            _toast = null;
        }
    }
}
