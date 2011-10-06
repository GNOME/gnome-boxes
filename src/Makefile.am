NULL =

AM_CPPFLAGS =						\
	-include config.h				\
	-DGNOMELOCALEDIR=\""$(datadir)/locale"\"	\
	$(DISABLE_DEPRECATED)				\
	$(NULL)

AM_VALAFLAGS =						\
	--vapidir=$(srcdir)/				\
	--vapidir=$(top_srcdir)/vapi                    \
	--pkg clutter-gtk-1.0				\
	--pkg cogl-1.0					\
	--pkg config					\
	--pkg posix					\
	--pkg gdk-pixbuf-2.0				\
	--pkg glib-2.0					\
	--pkg libvirt-gobject-1.0			\
	--pkg libxml-2.0				\
	--pkg spice-client-gtk-3.0			\
	$(NULL)

bin_PROGRAMS = gnome-boxes

gnome_boxes_SOURCES =				\
	app.vala				\
	box.vala				\
	collection-view.vala			\
	collection.vala				\
	display.vala				\
	main.vala				\
	sidebar.vala				\
	spice-display.vala			\
	topbar.vala				\
	util.vala				\
	$(NULL)
BUILT_SOURCES = dirs.h
gnome_boxes_LDADD = $(BOXES_LIBS)
gnome_boxes_CFLAGS = $(BOXES_CFLAGS)

DISTCLEANFILES = dirs.h
dirs.h: Makefile
	$(AM_V_GEN)echo '#define DATADIR "$(datadir)"' >$@

MAINTAINERCLEANFILES =				\
	$(gnome_boxes_SOURCES:.vala=.c)		\
	*.stamp					\
	$(NULL)

-include $(top_srcdir)/git.mk
