using Gtk;

private abstract class Boxes.AssistantPage : Gtk.Box {
    protected Object? artifact;
    public bool skip = false;
    protected signal void done (Object artifact);

    public virtual string title {
        protected set; get;
    }

    public async virtual void next () {
        done (artifact);
    }

    public abstract void cleanup ();
}
