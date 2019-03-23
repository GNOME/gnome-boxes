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

# **To check whether your system has Virtualization enabled or not:**

For **Linux**: Run: 
```
egrep vmx|svm /proc/cpuinf
```  
vmx : Intel  
svm : AMD
		
If you get something like:  
```
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx

 fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl 

xtopology nonstop_tsc cpuid aperfmperf tsc_known_freq pni pclmulqdq dtes64 monitor ds_cpl vmx est tm2 ssse3 sdbg

 fma cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm 

abm 3dnowprefetch cpuid_fault invpcid_single pti ssbd ibrs ibpb stibp tpr_shadow vnmi flexpriority ept vpid 

fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid mpx rdseed adx smap clflushopt intel_pt xsaveopt xsavec 

xgetbv1 xsaves dtherm ida arat pln pts hwp hwp_notify hwp_act_window hwp_epp flush_l1d 
```
then your system supports VT.

For **Windows**:
You can check in **Task Manager** -> **Performance** -> **CPU**

# **To enable Virtualization on your system:**

1. Reboot the system and open the **BIOS** menu
2. Select **Restore Defaults** option and then **Save & Exit**.
3. Reboot and again open **BIOS**
4. Open the **Processor** submenu in the **Chipset**, **Advanced CPU Configuration** or **Northbridge**.
5. Enable **Intel Virtualization Technology** (also known as **Intel VT**) or **AMD-V** depending on the brand of the processor. The virtualization extensions may be labeled **Virtualization Extensions**, **Vanderpool** or 
various other names depending on the OEM and system BIOS.
6. **Save & Exit**.
7. Reboot and run 
```
cat /proc/cpuinfo | grep vmx svm
```
If there is some output then the virtualization extensions are now enabled. If there is no output your system may not have the virtualization extensions or the correct BIOS setting enabled.



## References

* [GNOME Boxes](https://wiki.GNOME.org/ThreePointThree/Features/Boxes)
* [GNOME Boxes Wiki](https://wiki.GNOME.org/Design/Apps/Boxes)

