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

* genisoimage (usually provided by genisoimage package)
* mcopy (usually provided by mtools package)

# Reporting Bugs

If you want to report bugs, please check if there isn't already one on:

 [GNOME Boxes Issues](https://gitlab.GNOME.org/GNOME/GNOME-boxes/issues)

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

# Contributing

## Finding Bugs

Bugs labelled as "Newcomers" for the project can be found here:

[Newcomers Bugs](https://gitlab.gnome.org/GNOME/gnome-boxes/issues?label_name%5B%5D=4.+Newcomers)

## Building the Project

Instructions for building the project can be found here:

[Build the Project](https://wiki.gnome.org/Newcomers/BuildProject)

# Appendix

## Backtracing

* If you are not using the flatpak gnome-boxes package

```
gdb gnome-boxes
```

* If you using the flatpak gnome-boxes package

```
flatpak run --command=sh --devel org.gnome.Boxes
gdb /app/bin/gnome-boxes
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
G_MESSAGES_DEBUG=Boxes GNOME-boxes
```

If you want to run your jhbuild version, execute:

```
G_MESSAGES_DEBUG=Boxes jhbuild run GNOME-boxes
```

or start a shell under jhbuild environment:

```
G_MESSAGES_DEBUG=Boxes jhbuild shell
```

to be able to use simpler commands from there:

```
GNOME-boxes
```

## References

* [GNOME Boxes](https://wiki.GNOME.org/ThreePointThree/Features/Boxes)
* [GNOME Boxes Wiki](https://wiki.GNOME.org/Design/Apps/Boxes)

