NULL=
SUBDIRS = icons

desktopdir       = $(datadir)/applications
desktop_in_files = gnome-boxes.desktop.in
desktop_DATA     = $(desktop_in_files:.desktop.in=.desktop)
@INTLTOOL_DESKTOP_RULE@

styledir         = $(datadir)/gnome-boxes/style
style_DATA       = gtk-style.css

iconsdir = $(pkgdatadir)/icons

EXTRA_DIST =					\
	gnome-boxes.desktop.in			\
	$(desktop_in_files)			\
	$(NULL)

CLEANFILES =					\
	$(desktop_DATA)				\
	$(NULL)

DISTCLEANFILES =				\
	$(desktop_DATA)				\
	$(NULL)

-include $(top_srcdir)/git.mk
