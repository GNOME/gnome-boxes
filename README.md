# Introduction

A simple GNOME 3 application to access remote or virtual systems.

# Goals

* View, access, and use:
  * remote machines
  * remote virtual machines
  * local virtual machines
  * When technology permits, set up access for applications on local virtual machines
* View, access, and use virtual machines on removable media
* View, access, and use shared connection / machines
* Share connections?
* Upload / publish virtual machines
* Select favorites
* Search for connections

# Non-Goals

* Enterprise system management / administration
* Asset management
* Software distribution
* Automation

# Use Cases

* Connect to a local virtual machine for testing.
* Connecting to a work machine from home.
* Connect to a work machine over a low quality cellular network.

# Runtime Dependencies

* mcopy (usually provided by mtools package)

# Reporting Bugs

If you want to report bugs, please check if there isn't already one on:

 [Gnome Boxes Issues](https://gitlab.gnome.org/GNOME/gnome-boxes/issues)

If one does not exist already, please file a new one.

Please provide as much useful information as you can and have. This can
include

* steps to reproduce your problem
* the error message, if there is one (in the UI and on the console)
* a backtrace if the program crashes (See Appendix 1)
* debug messages if it makes sense (See Appendix 2)
* a fix if you have one (This greatly increases the chances of this issue
  getting fixed soon. See HACKING, section 2 for how to provide a good patch.)

The determination of what is useful is your task. If you forget about
something important, someone will probably ask.

# Appendix

## Backtracing

just run

```
jhbuild run gdb gnome-boxes
```

Type

```
run
```

Let the program crash.

Type:

```
backtrace
```

And copy the output to pastebin.com or a similar webpage and link it in the
bugtracker with a hint.

## Activating debug messages

To run Boxes with debug message output on the console, just run:

```
G_MESSAGES_DEBUG=Boxes gnome-boxes
```

If you want to run your jhbuild version, execute:

```
G_MESSAGES_DEBUG=Boxes jhbuild run gnome-boxes
```

or start a shell under jhbuild environment:

```
G_MESSAGES_DEBUG=Boxes jhbuild shell
```

to be able to use simpler commands from there:

```
gnome-boxes
```

## References

* [Gnome Boxes](https://wiki.gnome.org/ThreePointThree/Features/Boxes)
* [Gnome Boxes Wiki](https://wiki.gnome.org/Design/Apps/Boxes)

