// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-sidebar.ui")]
private class Boxes.WizardSidebar: Gtk.Box {
    [GtkChild]
    private Gtk.Label intro_label;
    [GtkChild]
    private Gtk.Label source_label;
    [GtkChild]
    private Gtk.Label preparation_label;
    [GtkChild]
    private Gtk.Label setup_label;
    [GtkChild]
    private Gtk.Label review_label;

    public void set_page (WizardPage wizard_page) {
        foreach (var label in get_children ())
            label.get_style_context ().remove_class ("boxes-wizard-current-page-label");

        Gtk.Label current_label = null;
        switch ((int) wizard_page) {
        case WizardPage.INTRODUCTION:
            current_label = intro_label;
            break;
        case WizardPage.SOURCE:
            current_label = source_label;
            break;
        case WizardPage.PREPARATION:
            current_label = preparation_label;
            break;
        case WizardPage.SETUP:
            current_label = setup_label;
            break;
        case WizardPage.REVIEW:
            current_label = review_label;
            break;
        }
        current_label.get_style_context ().add_class ("boxes-wizard-current-page-label");
    }
}
