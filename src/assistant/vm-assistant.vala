// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private abstract class Boxes.AssistantPage : Gtk.Box {
    protected Object? artifact;
    public bool skip = false;
    protected signal void done (Object artifact);

    public async virtual void next () {
        done (artifact);
    }

    public abstract void cleanup ();
}

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
    private Button previous_button;
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
    }

    [GtkCallback]
    private void update_titlebar_buttons () {
        var is_index = (pages.visible_child == index_page);
        var is_last = (pages.visible_child == review_page);

        next_button.visible = !is_index;
        next_button.label = is_last ? _("Create") : _("Next");
        previous_button.label = is_index ? _("Cancel") : _("Previous");
    }

    [GtkCallback]
    private void on_previous_button_clicked () {
        if (visible_page == index_page)
            close ();
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

        //App.app.main_window.select_item (machine);
        machine.domain.start (0);
        close ();
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/review-page.ui")]
private class Boxes.AssistantReviewPage : AssistantPage {

    [GtkChild]
    private WizardSummary summary;
    [GtkChild]
    private InfoBar nokvm_infobar;

    public async void setup (VMCreator vm_creator) {
        try {
            artifact = yield vm_creator.create_vm (null); // TODO: make it cancellable
        } catch (IOError.CANCELLED cancel_error) { // We did this, so ignore!
        } catch (GLib.Error error) {
            warning ("Box setup failed: %s", error.message);
        }

        yield populate (artifact as LibvirtMachine);
    }

    public async void populate (LibvirtMachine machine) {
        var vm_creator = machine.vm_creator;
        foreach (var property in vm_creator.install_media.get_vm_properties ())
            summary.add_property (property.first, property.second);

        try {
            var config = null as GVirConfig.Domain;
            yield App.app.async_launcher.launch (() => {
                config = machine.domain.get_config (GVir.DomainXMLFlags.INACTIVE);
            });

            var memory = format_size (config.memory * Osinfo.KIBIBYTES, FormatSizeFlags.IEC_UNITS);
            summary.add_property (_("Memory"), memory);
        } catch (GLib.Error error) {
            warning ("Failed to get configuration for machine '%s': %s", machine.name, error.message);
        }

        if (!machine.importing && machine.storage_volume != null) {
            try {
                var volume_info = machine.storage_volume.get_info ();
                var capacity = format_size (volume_info.capacity);
                summary.add_property (_("Disk"),
                                      // Translators: This is disk size. E.g "1 GB maximum".
                                      _("%s maximum").printf (capacity));
            } catch (GLib.Error error) {
                warning ("Failed to get information on volume '%s': %s",
                         machine.storage_volume.get_name (),
                         error.message);
            }

            nokvm_infobar.visible = (machine.domain_config.get_virt_type () != GVirConfig.DomainVirtType.KVM);

            // TODO: show customize button

        }
        print ("REview page setup done!\n");
    }

    public override void cleanup () {
        summary.clear ();
        nokvm_infobar.hide ();

        if (artifact != null) {
            App.app.delete_machine (artifact as Machine);
        }
    }

    public override async void next () {
        if (artifact == null) {
            var wait = notify["artifact"].connect (() => {
                next.callback ();
            });
            yield;
            disconnect (wait);
        }

        done (artifact);
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/setup-page.ui")]
private class Boxes.AssistantSetupPage : AssistantPage {
    [GtkChild]
    private Gtk.Box setup_box;

    public async void setup (VMCreator vm_creator) {
        this.artifact = vm_creator;

        vm_creator.install_media.populate_setup_box (setup_box);
        if (!vm_creator.install_media.need_user_input_for_vm_creation && vm_creator.install_media.ready_to_create)
            done (vm_creator);

        skip = !vm_creator.install_media.need_user_input_for_vm_creation;
    }

    public override async void next () {
        var vm_creator = artifact as VMCreator;
        if (vm_creator.install_media.ready_to_create) {
            done (vm_creator);
        }
    }

    public override void cleanup () {
        if (skip) {
            foreach (var child in setup_box.get_children ())
                child.destroy ();
        }
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/preparation-page.ui")]
private class Boxes.AssistantPreparationPage : AssistantPage {
    [GtkChild]
    private Gtk.Label media_label;
    [GtkChild]
    private Gtk.Label status_label;
    [GtkChild]
    private Gtk.Image installer_image;
    [GtkChild]
    private Gtk.ProgressBar progress_bar;

    private InstallerMedia _media;
    public InstallerMedia media {
        get { return _media; }
        set {
            _media = value;

            if (_media.os != null) {
                media_label.label = _media.os.name;
                Downloader.fetch_os_logo.begin (installer_image, _media.os, 128);
            }
        }
    }

    public void setup (InstallerMedia media) {
        try {
            var media_manager = MediaManager.get_instance ();
            media = media_manager.create_installer_media_from_media (media);
        } catch (GLib.Error error) {
            warning ("Failed to setup installation media '%s': %s", media.device_file, error.message);
        }

        prepare (media);

        skip = true;
    }

    public async void prepare (InstallerMedia media) {
        var progress = create_preparation_progress ();
        if (!yield media.prepare (progress, null)) // add cancellable
            return;

        progress_bar.fraction = 1.0;

        done (media.get_vm_creator ());
    }

    private ActivityProgress create_preparation_progress () {
        var progress = new ActivityProgress ();

        progress.notify["progress"].connect (() => {
            if (progress.progress - progress_bar.fraction >= 0.01)
                progress_bar.fraction = progress.progress;
        });
        progress_bar.fraction = progress.progress = 0;

        progress.bind_property ("info", status_label, "label");

        return progress;
    }

    public override void cleanup () {
        // reset cancellation singleton
    }
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/assistant/pages/index-page.ui")]
private class Boxes.AssistantIndexPage : AssistantPage {
    GLib.ListStore source_model = new GLib.ListStore (typeof (InstallerMedia));
    GLib.ListStore featured_model = new GLib.ListStore (typeof (Osinfo.Media));

    private const int MAX_MEDIA_ENTRIES = 3;

    [GtkChild]
    private Gtk.ListBox source_medias;
    [GtkChild]
    private Gtk.ListBox featured_medias;

    construct {
        populate_media_lists.begin ();

        source_medias.bind_model (source_model, add_media_entry);    
        featured_medias.bind_model (featured_model, add_featured_media_entry);
    }

    private async void populate_media_lists () {
        var media_manager = MediaManager.get_instance ();

        var source_medias = yield media_manager.list_installer_medias ();
        //for (var i = 0; i < MAX_MEDIA_ENTRIES; i++) {
        foreach (var media in source_medias) {
            source_model.append (media); 
        }

        var recommended_downloads = yield get_recommended_downloads ();
        for (var i = 0; i < MAX_MEDIA_ENTRIES; i++) {
            featured_model.append (recommended_downloads.nth (i).data);
        }
    }

    private Gtk.Widget add_media_entry (GLib.Object object) {
        return new WizardMediaEntry (object as InstallerMedia);
    }

    private Gtk.Widget add_featured_media_entry (GLib.Object object) {
        return new WizardDownloadableEntry (object as Osinfo.Media);
    }

    [GtkCallback]
    private void on_source_media_selected (Gtk.ListBoxRow row) {
        done ((row as WizardMediaEntry).media);
    }

    public override void cleanup () {
    }
}
