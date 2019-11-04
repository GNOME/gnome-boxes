// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/vm-assistant.ui")]
private class Boxes.VMAssistant : Gtk.Dialog {
    [GtkChild]
    private Stack pages;
    [GtkChild]
    private AssistantIndexPage index_page;
    [GtkChild]
    private AssistantPreparationPage preparation_page;
    [GtkChild]
    private AssistantSetupPage setup_page;
    [GtkChild]
    private AssistantReviewPage review_page;

    [GtkChild]
    public Button previous_button;
    [GtkChild]
    private Button next_button;

    private AssistantPage visible_page {
        get {
            return pages.get_visible_child () as AssistantPage;
        }
    }

    private AssistantPage? previous_page {
        get {
            var current_page_index = pages.get_children ().index (visible_page);
            return pages.get_children ().nth_data (current_page_index - 1) as AssistantPage;
        }
    }

    construct {
        use_header_bar = 1;
    }

    public VMAssistant (AppWindow app_window) {
        set_transient_for (app_window);

        // TODO: Make the Assistant independent from window states
        app_window.set_state (UIState.WIZARD);

        index_page.setup (app_window, this);
    }

    [GtkCallback]
    private void update_titlebar_buttons () {
        var is_index = (visible_page == index_page);
        var is_last = (visible_page == review_page);

        next_button.visible = !is_index;

        next_button.label = is_last ? _("Create") : _("Next");
        previous_button.label = is_index ? _("Cancel") : _("Previous");

        title = visible_page.title;
    }

    [GtkCallback]
    private void on_previous_button_clicked () {
        if (visible_page == index_page)
            index_page.go_back ();
        else
            go_back ();
    }

    private void go_back () {
        visible_page.cleanup ();

        pages.set_visible_child (previous_page);
        if (visible_page.skip)
            go_back ();
    }

    [GtkCallback]
    private void on_next_button_clicked () {
        visible_page.next ();
    }

    [GtkCallback]
    private void do_preparation (Object object) {
        pages.set_visible_child (preparation_page);

        preparation_page.setup (object as InstallerMedia);
    }

    [GtkCallback]
    private void do_setup (Object object) {
        pages.set_visible_child (setup_page);

        var vm_creator = object as VMCreator;
        vm_creator.install_media.bind_property ("ready-to-create",
                                                next_button, "sensitive",
                                                BindingFlags.SYNC_CREATE);

        setup_page.setup (vm_creator);
    }

    [GtkCallback]
    private async void do_review (Object object) {
        pages.set_visible_child (review_page);

        review_page.setup (object as VMCreator);
    }

    [GtkCallback]
    private async void do_create (Object object) {
        var machine = object as LibvirtMachine;

        var vm_creator = machine.vm_creator;
        try {
            vm_creator.launch_vm (machine);
        } catch (GLib.Error error) {
            warning ("Failed to create machine: %s", error.message);
        }

        vm_creator.install_media.clean_up_preparation_cache ();

        close ();
    }

    public override void close () {
        // TODO: Make the Assistant independent from window states
        App.app.main_window.set_state (UIState.COLLECTION);

        base.close ();
    }
}
