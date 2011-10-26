NULL =

AM_CPPFLAGS =						\
	-include config.h				\
	-DGNOMELOCALEDIR=\""$(datadir)/locale"\"	\
	$(DISABLE_DEPRECATED)				\
	$(NULL)

AM_VALAFLAGS =						\
	--vapidir=$(srcdir)/				\
	--vapidir=$(top_srcdir)/vapi                    \
	--vapidir=$(top_srcdir)/vapi/upstream           \
	--pkg clutter-gtk-1.0				\
	--pkg cogl-1.0					\
	--pkg config					\
	--pkg gdk-pixbuf-2.0				\
	--pkg glib-2.0					\
	--pkg libvirt-gobject-1.0			\
	--pkg libxml-2.0				\
	--pkg posix					\
	--pkg spice-client-gtk-3.0			\
	--pkg gtk-vnc-2.0				\
	$(NULL)

bin_PROGRAMS = gnome-boxes

gnome_boxes_SOURCES =				\
	app.vala				\
	collection-source.vala			\
	collection-view.vala			\
	collection.vala				\
	display-page.vala			\
	display.vala				\
	libvirt-machine.vala			\
	machine.vala				\
	main.vala				\
	remote-machine.vala			\
	sidebar.vala				\
	spice-display.vala			\
	topbar.vala				\
	ui.vala					\
	util.vala				\
	vnc-display.vala			\
	wizard-source.vala			\
	wizard.vala				\
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
