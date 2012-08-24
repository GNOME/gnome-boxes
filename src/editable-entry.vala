// This file is part of GNOME Boxes. License: LGPLv2+
// Boxes.EditableEntry is based on gnome-control-center CcEditableEntry

using Gtk;

private const string EMPTY_TEXT = "\xe2\x80\x94";

private class Boxes.EditableEntry: Alignment {
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
            (button.get_child () as Label).label = value;
        }
    }

    public bool _editable;
    public bool editable {
        get { return _editable; }
        set {
            if (value == _editable)
                return;

            _editable = value;
            notebook.page = editable ? Page.BUTTON : Page.LABEL;
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

    private Pango.Weight _weight = Pango.Weight.NORMAL;
	/* This is disabled for now since its impossible to
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

    private Gtk.Notebook notebook;
    private Gtk.Label label;
    private Gtk.Button button;
    private Gtk.Entry entry;

    private void update_entry_font (Gtk.Entry entry) {
        if (!scale_set && !weight_set)
            return;

        SignalHandler.block_by_func (entry, (void*)update_entry_font, this);

        entry.override_font (null);
        var desc = entry.get_style_context ().get_font (entry.get_state_flags ());
        if (weight_set)
            desc.set_weight (_weight);
        if (scale_set)
            desc.set_size ((int)(scale * desc.get_size ()));
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
        (button.get_child () as Label).set_attributes (attrs);
        update_entry_font (entry);
    }

    public void start_editing () {
        notebook.page = Page.ENTRY;
    }

    private bool in_stop_editing;
    private void stop_editing () {
        /* Avoid launching another "editing-done" signal
         * caused by the notebook page change */
        if (in_stop_editing)
            return;

        in_stop_editing = true;
        notebook.page = Page.BUTTON;
        text = entry.text;
        editing_done ();
        in_stop_editing = false;
    }

    private void cancel_editing () {
        entry.text = text;
        notebook.page = Page.BUTTON;
    }

    public EditableEntry () {
        notebook = new Gtk.Notebook ();
        notebook.show_tabs = false;
        notebook.show_border = false;

        label = new Gtk.Label (EMPTY_TEXT);
        label.set_alignment (0.0f, 0.5f);
        notebook.append_page (label, null);

        button = new Gtk.Button.with_label (EMPTY_TEXT);
        button.receives_default = true;
        button.relief = Gtk.ReliefStyle.NONE;
        button.set_alignment (0.0f, 0.5f);
        notebook.append_page (button, null);
        button.clicked.connect (() => {
            start_editing ();
        });

        (button.get_child ()).size_allocate.connect ((widget, allocation) => {
                Gtk.Allocation alloc;

                widget.get_parent ().get_allocation (out alloc);
                var offset = allocation.x - alloc.x;
                if (offset != label.xpad)
                    label.set_padding (offset, 0);

        });

        entry = new Gtk.Entry ();
        notebook.append_page (entry, null);
        entry.activate.connect (() => {
            stop_editing ();
        });

        entry.focus_out_event.connect (() => {
            stop_editing ();
            return false;
        });

        entry.key_press_event.connect ((widget, event) => {
            if (event.keyval == Gdk.Key.Escape)
                cancel_editing ();

            return false;
        });

        entry.style_updated.connect ((entry) => {
            update_entry_font (entry as Gtk.Entry);
        });

        notebook.page = Page.LABEL;
        this.add (notebook);
        this.show_all ();
    }
}
