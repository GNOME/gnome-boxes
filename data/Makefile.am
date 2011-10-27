NULL=
SUBDIRS = icons

desktopdir       = $(datadir)/applications
desktop_in_files = gnome-boxes.desktop.in
desktop_DATA     = $(desktop_in_files:.desktop.in=.desktop)
@INTLTOOL_DESKTOP_RULE@

gsettings_SCHEMAS = org.gnome.boxes.gschema.xml
@INTLTOOL_XML_NOMERGE_RULE@
@GSETTINGS_RULES@

styledir         = $(datadir)/gnome-boxes/style
style_DATA       = gtk-style.css

sourcedir         = $(datadir)/gnome-boxes/sources
source_DATA       = QEMU_Session

iconsdir = $(pkgdatadir)/icons

unattendeddir = $(datadir)/gnome-boxes/unattended
unattended_DATA = ks.cfg 			\
		  win7.xml 			\
		  win2k.xml 			\
		  winxp.sif 			\
		  win2k.sif 			\
		  win2k3.sif 			\
		  floppy.img			\
		  $(NULL)

floppy.img:
	rm -f floppy.img && mkfs.msdos -C floppy.img 2048

EXTRA_DIST =					\
	gnome-boxes.desktop.in			\
	org.gnome.boxes.gschema.xml.in		\
	$(desktop_in_files)			\
	$(NULL)

CLEANFILES =					\
	$(desktop_DATA)				\
	$(NULL)

DISTCLEANFILES =				\
	$(desktop_DATA)				\
	$(NULL)

-include $(top_srcdir)/git.mk
