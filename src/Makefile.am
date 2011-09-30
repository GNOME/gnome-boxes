NULL =

AM_CPPFLAGS =						\
	-DGNOMELOCALEDIR=\""$(datadir)/locale"\"	\
	$(DISABLE_DEPRECATED)				\
	$(NULL)

AM_VALAFLAGS =						\
	--vapidir=$(srcdir)/				\
	--pkg config					\
	--pkg glib-2.0					\
	--pkg clutter-gtk-1.0				\
	$(NULL)

bin_PROGRAMS = boxes

boxes_SOURCES = boxes.vala
boxes_LDADD = $(BOXES_LIBS)
boxes_CFLAGS = $(BOXES_CFLAGS)
