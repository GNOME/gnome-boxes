// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;
using Clutter;

private enum Boxes.SidebarPage {
    COLLECTION,
    WIZARD,
    PROPERTIES,
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/sidebar.ui")]
private class Boxes.Sidebar: Gtk.Notebook, Boxes.UI {
    public Clutter.Actor actor { get { return gtk_actor; } }
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    private GtkClutter.Actor gtk_actor; // the sidebar box

    [GtkChild]
    private Gtk.Box wizard_vbox;
    [GtkChild]
    private Gtk.Label wizard_intro_label;
    [GtkChild]
    private Gtk.Label wizard_source_label;
    [GtkChild]
    private Gtk.Label wizard_preparation_label;
    [GtkChild]
    private Gtk.Label wizard_setup_label;
    [GtkChild]
    private Gtk.Label wizard_review_label;

    public Sidebar () {
        notify["ui-state"].connect (ui_state_changed);
        setup_sidebar ();
    }

    public void set_wizard_page (WizardPage wizard_page) {
        foreach (var label in wizard_vbox.get_children ())
            label.get_style_context ().remove_class ("boxes-wizard-current-page-label");

        Gtk.Label current_label = null;
        switch ((int) page_num) {
        case WizardPage.INTRODUCTION:
            current_label = wizard_intro_label;
            break;
        case WizardPage.SOURCE:
            current_label = wizard_source_label;
            break;
        case WizardPage.PREPARATION:
            current_label = wizard_preparation_label;
            break;
        case WizardPage.SETUP:
            current_label = wizard_setup_label;
            break;
        case WizardPage.REVIEW:
            current_label = wizard_review_label;
            break;
        }
        current_label.get_style_context ().add_class ("boxes-wizard-current-page-label");
    }

    private void ui_state_changed () {
        switch (ui_state) {
        case UIState.WIZARD:
        case UIState.PROPERTIES:
            App.app.sidebar_revealer.reveal ();
            page = ui_state == UIState.WIZARD ? SidebarPage.WIZARD : SidebarPage.PROPERTIES;
            break;

        default:
            App.app.sidebar_revealer.unreveal ();
            break;
        }
    }

    private void setup_sidebar () {
        gtk_actor = new GtkClutter.Actor.with_contents (this);
        gtk_actor.get_widget ().get_style_context ().add_class ("boxes-bg");
        gtk_actor.name = "sidebar";
        gtk_actor.x_expand = true;
        gtk_actor.y_expand = true;
    }
}
