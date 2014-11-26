// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-toolbar.ui")]
private class Boxes.WizardToolbar: HeaderBar {
    [GtkChild]
    public Button cancel_btn;
    [GtkChild]
    public Button back_btn;
    [GtkChild]
    public Button continue_btn;
    [GtkChild]
    public Button create_btn;

    public void click_back_button () {
        if (back_btn.sensitive)
            back_btn.clicked ();
    }

    public void click_forward_button () {
        if (continue_btn.sensitive)
            continue_btn.clicked ();
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
}
