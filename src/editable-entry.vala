// This file is part of GNOME Boxes. License: LGPLv2+
// Boxes.EditableEntry is based on gnome-control-center CcEditableEntry

using Gtk;

private const string EMPTY_TEXT = "\xe2\x80\x94";

[GtkTemplate (ui = "/org/gnome/Boxes/ui/editable-entry.ui")]
private class Boxes.EditableEntry: Notebook {
    private enum Page {
        LABEL,
        BUTTON,
        ENTRY
    }

    public signal void editing_done ();

    private string _text;
    public string text {
        get { return _text; }
        set {
            _text = value;
            entry.text = value;

            if (value == null || value.length == 0)
                value = EMPTY_TEXT;

            label.label = value;
            button_label.label = value;
        }
    }

    public bool _editable;
    public bool editable {
        get { return _editable; }
        set {
            if (value == _editable)
                return;

            _editable = value;
            page = editable ? Page.BUTTON : Page.LABEL;
        }
    }

    public bool selectable {
        get { return label.selectable; }
        set {
            if (value == label.selectable)
                return;

            label.selectable = value;
        }
    }

    public float text_xalign {
        get { return label.xalign; }
        set {
            label.xalign = value;
            button_label.xalign = value;
            entry.xalign = value;
        }
    }

    public float text_yalign {
        get { return label.yalign; }
        set {
            label.yalign = value;
            button_label.yalign = value;
        }
    }

    private Pango.Weight _weight = Pango.Weight.NORMAL;
    /* This is disabled for now since it's impossible to
       declare a default for the paramspec, and the number that
       valac picks (0) is invalid for the Pango.Weight enum.

    public Pango.Weight weight {
        get { return _weight; }
        set {
            if (value == _weight && weight_set)
                return;

            _weight = value;
            weight_set = true;

            update_fonts ();
        }
    }
    */
    public bool weight_set { get; set; }

    private double _scale = 1.0;
    public double scale {
        get { return _scale; }
        set {
            if (value == _scale && scale_set)
                return;

            _scale = value;
            scale_set = true;

            update_fonts ();
        }
    }
    public bool scale_set { get; set; }

    [GtkChild]
    private unowned Gtk.Label label;
    [GtkChild]
    private unowned Gtk.Label button_label;
    [GtkChild]
    private unowned Gtk.Entry entry;

    private void update_entry_font (Gtk.Entry entry) {
        if (!scale_set && !weight_set)
            return;

        SignalHandler.block_by_func (entry, (void*)update_entry_font, this);

        entry.override_font (null);
        var desc = entry.get_style_context ().get_font (entry.get_state_flags ());
        if (weight_set)
            desc.set_weight (_weight);
        if (scale_set)
            desc.set_size ((int) (scale * desc.get_size ()));
        entry.override_font (desc);

        SignalHandler.unblock_by_func (entry, (void*)update_entry_font, this);
    }

    private void update_fonts () {
        var attrs = new Pango.AttrList ();

        if (scale_set)
            attrs.insert (Pango.attr_scale_new (scale));
        if (weight_set)
            attrs.insert (Pango.attr_weight_new (_weight));

        label.set_attributes (attrs);
        button_label.set_attributes (attrs);
        update_entry_font (entry);
    }

    public void start_editing () {
        page = Page.ENTRY;
    }

    private bool in_stop_editing;
    private void stop_editing () {
        /* Avoid launching another "editing-done" signal
         * caused by the notebook page change */
        if (in_stop_editing)
            return;

        in_stop_editing = true;
        page = Page.BUTTON;
        text = entry.text;
        editing_done ();
        in_stop_editing = false;
    }

    private void cancel_editing () {
        entry.text = text;
        page = Page.BUTTON;
    }

    public EditableEntry () {
        label.label = EMPTY_TEXT;
        button_label.label = EMPTY_TEXT;
    }

    [GtkCallback]
    private void on_button_clicked () {
        start_editing ();
    }

    [GtkCallback]
    private void on_button_label_size_allocate (Gtk.Widget widget, Gtk.Allocation allocation) {
        Gtk.Allocation alloc;

        widget.get_parent ().get_allocation (out alloc);
        var offset = allocation.x - alloc.x;
        if (offset != label.margin_start)
            label.set_padding (offset, 0);
    }

    [GtkCallback]
    private void on_entry_activated () {
        stop_editing ();
    }

    [GtkCallback]
    private bool on_entry_focused_out () {
        stop_editing ();
        return false;
    }

    [GtkCallback]
    private bool on_entry_key_press_event (Gtk.Widget widget, Gdk.EventKey event) {
        if (event.keyval == Gdk.Key.Escape)
            cancel_editing ();

        return false;
    }

    [GtkCallback]
    private void on_entry_style_updated () {
        update_entry_font (entry as Gtk.Entry);
    }
}
