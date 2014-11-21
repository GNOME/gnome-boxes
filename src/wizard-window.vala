// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-window.ui")]
private class Boxes.WizardWindow : Gtk.Window, Boxes.UI {
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    [GtkChild]
    public WizardSidebar sidebar;
    [GtkChild]
    public Wizard wizard;
    [GtkChild]
    public WizardToolbar topbar;

    public WizardWindow (AppWindow app_window) {
        wizard.setup_ui (app_window, this);

        set_transient_for (app_window);

        notify["ui-state"].connect (ui_state_changed);
    }

    public void set_title_for_page (WizardPage page) {
        switch (page) {
        case WizardPage.LAST:

            break;
        case WizardPage.INTRODUCTION:
            title = _("Create a box");

            break;
        default:
            title = _("Create a box (step %d/5)").printf (page);

            break;
        }
    }

    private void ui_state_changed () {
        wizard.set_state (ui_state);

        this.visible = (ui_state == UIState.WIZARD);
    }

    [GtkCallback]
    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        var default_modifiers = Gtk.accelerator_get_default_mod_mask ();

        if (event.keyval == Gdk.Key.Left && // ALT + Left -> back
                   (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            topbar.click_back_button ();
            return true;
        } else if (event.keyval == Gdk.Key.Right && // ALT + Right -> forward
                   (event.state & default_modifiers) == Gdk.ModifierType.MOD1_MASK) {
            topbar.click_forward_button ();
            return true;
        } else if (event.keyval == Gdk.Key.Escape) { // ESC -> cancel
            topbar.cancel_btn.clicked ();
        }

        return false;
    }

    [GtkCallback]
    private bool on_delete_event () {
        wizard.cancel ();

        return true;
    }
}
