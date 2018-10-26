// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/wizard-toolbar.ui")]
private class Boxes.WizardToolbar: Gtk.Stack {
    private const string[] page_titles = { N_("Source Selection"),
                                           N_("Box Preparation"),
                                           N_("Box Setup"),
                                           N_("Review"),
                                           "" };

    private WizardWindowPage _page;
    public WizardWindowPage page {
        get { return _page; }
        set {
            _page = value;

            visible_child_name = WizardWindow.page_names[value];
        }
    }

    [GtkChild]
    private Gtk.HeaderBar main;

    [GtkChild]
    public Button cancel_btn;
    [GtkChild]
    public Button back_btn;
    [GtkChild]
    public Button continue_btn;
    [GtkChild]
    public Button create_btn;
    [GtkChild]
    public SearchEntry downloads_search;

    private unowned WizardWindow wizard_window;

    public string title {
        get { return main.title; }
        set { main.title = value; }
    }

    public void setup_ui (WizardWindow wizard_window) {
        this.wizard_window = wizard_window;
    }

    public void click_back_button () {
        if (back_btn.sensitive)
            back_btn.clicked ();
    }

    public void click_forward_button () {
        if (continue_btn.sensitive)
            continue_btn.clicked ();
    }

    public void set_title_for_page (WizardPage page) {
        main.title = _(page_titles[page]);
    }

    [GtkCallback]
    private void on_back_button_clicked () {
        downloads_search.set_text ("");

        wizard_window.page = WizardWindowPage.MAIN;
    }
}
