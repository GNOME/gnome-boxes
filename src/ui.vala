// This file is part of GNOME Boxes. License: LGPLv2+

private enum Boxes.UIState {
    NONE,
    COLLECTION,
    CREDS,
    DISPLAY,
    SETTINGS,
    WIZARD
}

private abstract class Boxes.UI: GLib.Object {
    public abstract Clutter.Actor actor { get; }

    private UIState _ui_state;
    [CCode (notify = false)]
    public UIState ui_state {
        get { return _ui_state; }
        set {
            if (_ui_state != value) {
                _ui_state = value;
                ui_state_changed ();
                notify_property ("ui-state");
            }
        }
    }

    public abstract void ui_state_changed ();
}

