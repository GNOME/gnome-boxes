// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

private enum Boxes.PropertiesPage {
    LOGIN,
    DISPLAY,
    DEVICES,

    LAST,
}

private class Boxes.Properties: Boxes.UI {
    public override Clutter.Actor actor { get { return gtk_actor; } }

    private GtkClutter.Actor gtk_actor;
    private Boxes.App app;
    private Gtk.Notebook notebook;
    private Gtk.ToolButton back;
    private Gtk.Label toolbar_label;
    private Gtk.ListStore listmodel;
    private Gtk.TreeView tree_view;

    private class PageWidget {
        public Gtk.Widget widget;
        public string name;

        private Gtk.Table table;

        public PageWidget (PropertiesPage page, Machine machine) {
            switch (page) {
            case PropertiesPage.LOGIN:
                name = _("Login");
                break;

            case PropertiesPage.DISPLAY:
                name = _("Display");
                break;

            case PropertiesPage.DEVICES:
                name = _("Devices");
                break;
            }

            var vbox = new Gtk.VBox (false, 10);
            table = new Gtk.Table (1, 2, false);
            vbox.pack_start (table, false, false, 0);
            table.margin = 20;
            table.row_spacing = 10;
            table.column_spacing = 20;

            table.resize (1, 2);
            var label = new Gtk.Label (name);
            label.get_style_context ().add_class ("boxes-step-label");
            label.margin_bottom = 10;
            label.xalign = 0.0f;
            table.attach_defaults (label, 0, 2, 0, 1);

            vbox.show_all ();
            widget = vbox;
        }

        public bool is_empty () {
            return false;
        }
    }

    public Properties (App app) {
        this.app = app;

        setup_ui ();
    }

    private void list_append (Gtk.ListStore listmodel, string label) {
        Gtk.TreeIter iter;

        listmodel.append (out iter);
        listmodel.set (iter, 0, label);
    }

    private void populate () {
        listmodel.clear ();
        for (var i = 0; i < PropertiesPage.LAST; i++)
            notebook.remove_page (i);

        if (app.current_item == null)
            return;

        for (var i = 0; i < PropertiesPage.LAST; i++) {
            var page = new PageWidget (i, app.current_item as Machine);
            notebook.append_page (page.widget, null);

            if (!page.is_empty ())
                list_append (listmodel, page.name);
        }

        tree_view.get_selection ().select_path (new Gtk.TreePath.from_string ("0"));
    }

    private void setup_ui () {
        notebook = new Gtk.Notebook ();
        notebook.show_tabs = false;
        notebook.get_style_context ().add_class ("boxes-bg");
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);

        /* topbar */
        var hbox = app.topbar.notebook.get_nth_page (Boxes.TopbarPage.PROPERTIES) as Gtk.HBox;

        var toolbar = new Toolbar ();
        toolbar.set_valign (Align.CENTER);
        toolbar.icon_size = IconSize.MENU;
        toolbar.get_style_context ().add_class (STYLE_CLASS_MENUBAR);
        toolbar.set_show_arrow (false);

        var toolbar_box = new Gtk.HBox (false, 0);
        toolbar_box.set_size_request (50, (int) Boxes.Topbar.height);
        toolbar_box.add (toolbar);

        var box = new Gtk.HBox (false, 5);
        box.add (new Gtk.Image.from_icon_name ("go-previous-symbolic", Gtk.IconSize.MENU));
        toolbar_label = new Gtk.Label ("label");
        box.add (toolbar_label);
        back = new ToolButton (box, null);
        back.get_style_context ().add_class ("raised");
        back.clicked.connect ((button) => { app.ui_state = UIState.DISPLAY; });
        toolbar.insert (back, 0);
        hbox.pack_start (toolbar_box, true, true, 0);

        hbox.show_all ();

        /* sidebar */
        var vbox = app.sidebar.notebook.get_nth_page (Boxes.SidebarPage.PROPERTIES) as Gtk.VBox;

        var image = new Gtk.Image ();
        image.set_size_request (180, 125);
        image.margin = 15;
        vbox.pack_start (image, false, false, 0);

        tree_view = new Gtk.TreeView ();
        var selection = tree_view.get_selection ();
        selection.set_mode (Gtk.SelectionMode.BROWSE);
        tree_view_activate_on_single_click (tree_view, true);
        tree_view.row_activated.connect ( (treeview, path, column) => {
            notebook.page = path.get_indices ()[0];
        });

        listmodel = new Gtk.ListStore (1, typeof (string));
        tree_view.set_model (listmodel);
        tree_view.headers_visible = false;
        var renderer = new CellRendererText ();
        tree_view.insert_column_with_attributes (-1, "", renderer, "text", 0);
        vbox.pack_start (tree_view, true, true, 0);

        vbox.show_all ();
        notebook.show_all ();
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.PROPERTIES:
            toolbar_label.label = app.current_item.name;
            populate ();
            break;
        }
    }
}
