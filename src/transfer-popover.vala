// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;

[GtkTemplate (ui = "/org/gnome/Boxes/ui/transfer-popover.ui")]
private class Boxes.TransferPopover: Gtk.Popover {
    [GtkChild]
    public unowned Gtk.Box transfers_container;

    public GLib.List<Spice.FileTransferTask> spice_tasks;
    public double progress { get; set; }

    private const uint remove_id_timeout = 5000;  // 5 seconds
    private ulong total_bytes_id = 0;
    private Boxes.DisplayToolbar display_toolbar;

    public TransferPopover (Boxes.DisplayToolbar toolbar) {
        display_toolbar = toolbar;
        relative_to = display_toolbar.transfers_button;

        display_toolbar.transfers_button.clicked.connect (() => {
            if (visible)
                popdown ();
            else
                popup ();
        });

        bind_property ("progress", display_toolbar, "progress", BindingFlags.DEFAULT);
    }

    public void add_transfer (Object transfer_task) {
        if (transfer_task is Spice.FileTransferTask) {
            var spice_transfer_task = transfer_task as Spice.FileTransferTask;

            add_spice_transfer (spice_transfer_task);
        } else {
            warning ("File transfer of unsupported type.");
        }

        popup ();
    }

    public void add_spice_transfer (Spice.FileTransferTask transfer_task) {
        spice_tasks.append (transfer_task);

        var row = new Boxes.TransferInfoRow (transfer_task.file.get_basename ());
        transfer_task.bind_property ("transferred-bytes", row, "transferred-bytes", BindingFlags.SYNC_CREATE);

        total_bytes_id = transfer_task.notify["total-bytes"].connect ( (t, p) => {
            row.total_bytes = transfer_task.total_bytes;

            transfer_task.disconnect (total_bytes_id);
        });

        transfer_task.notify["progress"].connect ( (t, p) => {
            row.progress = transfer_task.progress;

            double total = 0;
            double transferred = 0;
            foreach (var task in spice_tasks) {
               total += task.get_total_bytes ();
               transferred += task.get_transferred_bytes ();
            }

            progress = transferred/total;
        });
        transfer_task.finished.connect ( (transfer_task, error) => {
            if (error != null)
                warning (error.message);

            row.finalize_transfer ();
            spice_tasks.remove (transfer_task);

            if (spice_tasks.length () == 0) {
                Timeout.add (remove_id_timeout, () => {
                    on_transfer_finished ();

                    return false;
                });
            }

        });
        row.finished.connect (() => {
            spice_tasks.remove(transfer_task);

            if (spice_tasks.length () == 0) {
                Timeout.add (remove_id_timeout, () => {
                        on_transfer_finished ();

                        return false;
                    });
                }
        });

        transfers_container.pack_start (row);
        row.show ();
    }

    public void clean_up () {
        foreach (var row in transfers_container.get_children ()) {
            transfers_container.remove (row);
        }

        popdown ();
        display_toolbar.progress = 0;
        display_toolbar.transfers_button.hide ();
    }

    private void on_transfer_finished () {
        clean_up ();
        popdown ();
    }
}
