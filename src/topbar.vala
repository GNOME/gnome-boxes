// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gtk;

public enum Boxes.TopbarPage {
    COLLECTION,
    SELECTION,
    WIZARD,
    PROPERTIES
}

private class Boxes.Topbar: Boxes.UI {
    public override Clutter.Actor actor { get { return gtk_actor; } }
    public Gtk.Label label;

    public const uint height = 50;

    private GtkClutter.Actor gtk_actor; // the topbar box
    public Notebook notebook;

    private Gtk.Spinner spinner;
    private Gtk.ToggleToolButton select_btn;
    private Gtk.ToolButton cancel_btn;
    private Gtk.ToolButton spinner_btn;
    private Gtk.ToolButton back_btn;
    private Gtk.Button new_btn;
    private Gtk.Label selection_label;

    public Topbar () {
        setup_topbar ();

        App.app.notify["selected-items"].connect (() => {
            update_selection_label ();
        });
    }

    private void setup_topbar () {
        notebook = new Gtk.Notebook ();
        notebook.set_size_request (50, (int) height);
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);
        gtk_actor.name = "topbar";

        /* TopbarPage.COLLECTION */
        var hbox = new Gtk.HBox (false, 0);
        notebook.append_page (hbox, null);
        hbox.get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);

        var toolbar_start = new Gtk.Toolbar ();
        toolbar_start.icon_size = Gtk.IconSize.MENU;
        toolbar_start.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);
        toolbar_start.set_show_arrow (false);
        hbox.pack_start (toolbar_start, true, true, 0);

        back_btn = new Gtk.ToolButton (null, null);
        back_btn.valign = Gtk.Align.CENTER;
        back_btn.icon_name =  "go-previous-symbolic";
        back_btn.get_style_context ().add_class ("raised");
        back_btn.clicked.connect ((button) => { App.app.ui_state = UIState.COLLECTION; });
        toolbar_start.insert (back_btn, 0);

        new_btn = new Gtk.Button.with_label (_("New"));
        new_btn.set_size_request (70, -1);
        new_btn.get_style_context ().add_class ("raised");
        var tool_item = new Gtk.ToolItem ();
        tool_item.child = new_btn;
        tool_item.valign = Gtk.Align.CENTER;
        new_btn.clicked.connect ((button) => { App.app.ui_state = UIState.WIZARD; });
        toolbar_start.insert (tool_item, 1);

        label = new Gtk.Label ("");
        label.name = "TopbarLabel";
        label.set_halign (Gtk.Align.START);
        tool_item = new Gtk.ToolItem ();
        tool_item.set_expand (true);
        tool_item.child = label;
        toolbar_start.insert (tool_item, 2);

        var toolbar_end = new Gtk.Toolbar ();
        toolbar_end.icon_size = Gtk.IconSize.MENU;
        toolbar_end.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);

        spinner = new Gtk.Spinner ();
        spinner.start ();
        spinner_btn = new Gtk.ToolButton (spinner, null);
        spinner_btn.valign = Gtk.Align.CENTER;
        spinner_btn.get_style_context ().add_class ("raised");
        toolbar_end.insert (spinner_btn, 0);

        select_btn = new Gtk.ToggleToolButton ();
        select_btn.icon_name = "emblem-default-symbolic";
        select_btn.get_style_context ().add_class ("raised");
        select_btn.valign = Gtk.Align.CENTER;
        select_btn.clicked.connect (() => {
            notebook.page = TopbarPage.SELECTION;
            App.app.selection_mode = true;
        });
        update_select_btn_sensitivity ();
        App.app.collection.item_added.connect (update_select_btn_sensitivity);
        App.app.collection.item_removed.connect (update_select_btn_sensitivity);
        toolbar_end.insert (select_btn, 1);

        toolbar_end.set_show_arrow (false);
        hbox.pack_start (toolbar_end, false, false, 0);

        /* TopbarPage.SELECTION */
        hbox = new Gtk.HBox (false, 0);
        notebook.append_page (hbox, null);
        hbox.get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);

        var toolbar_selection = new Gtk.Toolbar ();
        toolbar_selection.set_style (Gtk.ToolbarStyle.TEXT);
        toolbar_selection.get_style_context ().add_class (Gtk.STYLE_CLASS_MENUBAR);
        toolbar_selection.icon_size = Gtk.IconSize.MENU;
        toolbar_selection.set_show_arrow (false);
        hbox.pack_start (toolbar_selection, true, true, 0);

        selection_label = new Gtk.Label ("");
        update_selection_label ();
        selection_label.use_markup = true;
        tool_item = new Gtk.ToolItem ();
        tool_item.set_expand (true);
        tool_item.child = selection_label;
        toolbar_selection.insert (tool_item, 0);

        cancel_btn = new Gtk.ToolButton.from_stock ("gtk-cancel");
        cancel_btn.get_style_context ().add_class ("raised");
        cancel_btn.valign = Gtk.Align.CENTER;
        toolbar_selection.insert (cancel_btn, 1);
        cancel_btn.clicked.connect (() => {
            select_btn.active = false;
            App.app.selection_mode = false;
            notebook.page = TopbarPage.COLLECTION;
        });

        /* TopbarPage.WIZARD */
        hbox = new Gtk.HBox (false, 0);
        hbox.margin = 5;
        notebook.append_page (hbox, null);
        hbox.get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);

        /* TopbarPage.PROPERTIES */
        hbox = new Gtk.HBox (false, 0);
        notebook.append_page (hbox, null);
        hbox.get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);

        notebook.show_tabs = false;
        notebook.show_all ();
    }

    private void update_select_btn_sensitivity () {
        select_btn.sensitive = App.app.collection.items.length != 0;
    }

    private void update_selection_label () {
        var items = App.app.selected_items.length ();
        if (items > 0)
            selection_label.set_markup ("<b>" + ngettext ("%d selected", "%d selected", items).printf (items) + "</b>");
        else
            selection_label.set_markup ("<i>" + _("Click on items to select them") + "</i>");
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.COLLECTION:
            notebook.page = TopbarPage.COLLECTION;
            back_btn.hide ();
            spinner_btn.hide ();
            select_btn.show ();
            new_btn.show ();
            break;

        case UIState.CREDS:
            new_btn.hide ();
            back_btn.show ();
            spinner_btn.show ();
            select_btn.hide ();
            break;

        case UIState.DISPLAY:
            break;

        case UIState.PROPERTIES:
            notebook.page = TopbarPage.PROPERTIES;
            break;

        case UIState.WIZARD:
            notebook.page = TopbarPage.WIZARD;
            break;

        default:
            break;
        }
    }
}
