// This file is part of GNOME Boxes. License: LGPLv2+

public class Boxes.AsyncLauncher {
    public delegate void RunInThreadFunc () throws  GLib.Error;

    private static AsyncLauncher launcher = null;

    private GLib.List<GLib.Thread<void *>> all_threads;

    public static AsyncLauncher get_default () {
        if (launcher == null)
            launcher = new AsyncLauncher ();

        return launcher;
    }

    private AsyncLauncher () {
        all_threads = new GLib.List<GLib.Thread<void *>> ();
    }

    public async void launch (owned RunInThreadFunc func) throws GLib.Error {
        GLib.Error e = null;
        GLib.SourceFunc resume = launch.callback;
        var thread = new GLib.Thread<void*> (null, () => {
            try {
                func ();
            } catch (GLib.Error err) {
                e = err;
            }

            Idle.add ((owned) resume);

            return null;
        });

        all_threads.append (thread);

        yield;

        thread.join();
        all_threads.remove (thread);

        if (e != null)
            throw e;
    }

    public void await_all () {
        foreach (var thread in all_threads)
            thread.join ();
    }
}
