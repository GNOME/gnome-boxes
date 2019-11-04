using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/setup-page.ui")]
private class Boxes.AssistantSetupPage : AssistantPage {
    [GtkChild]
    private Box setup_box;

    public async void setup (VMCreator vm_creator) {
        this.artifact = vm_creator;

        vm_creator.install_media.populate_setup_box (setup_box);
        if (!vm_creator.install_media.need_user_input_for_vm_creation &&
             vm_creator.install_media.ready_to_create) {
            done (vm_creator);
        }

        skip = !vm_creator.install_media.need_user_input_for_vm_creation;
    }

    public override async void next () {
        var vm_creator = artifact as VMCreator;
        if (vm_creator.install_media.ready_to_create) {
            done (vm_creator);
        }
    }

    public override void cleanup () {
        if (!skip)
            return;

        foreach (var child in setup_box.get_children ())
            child.destroy ();
    }
}
