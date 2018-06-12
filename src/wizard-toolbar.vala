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

    [GtkChild]
    private Button file_chooser_open_button;

    private unowned WizardWindow wizard_window;

    public void setup_ui (WizardWindow wizard_window) {
        this.wizard_window = wizard_window;

        var file_chooser = wizard_window.file_chooser;
        file_chooser.selection_changed.connect (() => {
            var path = file_chooser.get_filename ();

            file_chooser_open_button.sensitive = (path != null);
        });
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

    [GtkCallback]
    private void on_file_chooser_open_clicked () requires (page == WizardWindowPage.FILE_CHOOSER) {
        var file_chooser = wizard_window.file_chooser;
        var file = file_chooser.get_file ();
        assert (file != null);
        var file_type = file.query_file_type (FileQueryInfoFlags.NONE, null);

        switch (file_type) {
        case GLib.FileType.REGULAR:
        case GLib.FileType.SYMBOLIC_LINK:
            file_chooser.file_activated ();
            break;

        case GLib.FileType.DIRECTORY:
            file_chooser.set_current_folder (file.get_path ());
            break;

        default:
            debug ("Unknown file type selected");
            break;
        }
    }
}
