NULL =

AM_CPPFLAGS =						\
	-DGNOMELOCALEDIR=\""$(datadir)/locale"\"	\
	$(DISABLE_DEPRECATED)				\
	$(NULL)

AM_VALAFLAGS =						\
	--vapidir=$(srcdir)/				\
	--vapidir=$(top_srcdir)/vapi                    \
	--pkg config					\
	--pkg glib-2.0					\
	--pkg clutter-gtk-1.0				\
	--pkg spice-client-gtk-3.0			\
	--pkg libvirt-gobject-1.0			\
	$(NULL)

bin_PROGRAMS = boxes

boxes_SOURCES = boxes.vala box.vala collection.vala util.vala collection-view.vala sidebar.vala topbar.vala
BUILT_SOURCES = dirs.h
boxes_LDADD = $(BOXES_LIBS)
boxes_CFLAGS = $(BOXES_CFLAGS)

DISTCLEANFILES = dirs.h
dirs.h: Makefile
	echo '#define DATADIR "$(datadir)"' >$@
