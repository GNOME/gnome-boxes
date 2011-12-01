NULL =

AM_CPPFLAGS =						\
	-include config.h				\
	-DGNOMELOCALEDIR=\""$(datadir)/locale"\"	\
	-DDATADIR=\""$(datadir)"\"			\
	$(DISABLE_DEPRECATED)				\
	-DG_LOG_DOMAIN=\""Boxes"\"			\
	$(NULL)

AM_VALAFLAGS =						\
	--enable-experimental				\
	--vapidir=$(srcdir)/				\
	--vapidir=$(top_srcdir)/vapi                    \
	--vapidir=$(top_srcdir)/vapi/upstream           \
	--pkg clutter-gtk-1.0				\
	--pkg cogl-1.0					\
	--pkg config					\
	--pkg gdk-pixbuf-2.0				\
	--pkg glib-2.0					\
	--pkg gtk-vnc-2.0				\
	--pkg gudev-1.0					\
	--pkg libosinfo-1.0				\
	--pkg libvirt-gconfig-1.0			\
	--pkg libvirt-gobject-1.0			\
	--pkg libxml-2.0				\
	--pkg posix					\
	--pkg spice-client-gtk-3.0			\
	$(NULL)

bin_PROGRAMS = gnome-boxes

gnome_boxes_SOURCES =				\
	app.vala				\
	collection-source.vala			\
	collection-view.vala			\
	collection.vala				\
	display-config.vala			\
	display-page.vala			\
	display.vala				\
	editable-entry.vala			\
	fedora-installer.vala 			\
	installer-media.vala 			\
	libvirt-machine.vala			\
	machine.vala				\
	menu-box.vala				\
	mini-graph.vala				\
	main.vala				\
	os-database.vala 			\
	properties.vala				\
	remote-machine.vala			\
	selectionbar.vala			\
	sidebar.vala				\
	spice-display.vala			\
	topbar.vala				\
	ui.vala					\
	unattended-installer.vala 		\
	util.vala				\
	vm-creator.vala 			\
	vm-configurator.vala 			\
	vnc-display.vala			\
	win7-installer.vala 			\
	winxp-installer.vala 			\
	wizard-source.vala			\
	wizard.vala				\
	$(NULL)

gnome_boxes_LDADD = $(BOXES_LIBS)
gnome_boxes_CFLAGS = $(BOXES_CFLAGS)

MAINTAINERCLEANFILES =				\
	$(gnome_boxes_SOURCES:.vala=.c)		\
	*.stamp					\
	$(NULL)

-include $(top_srcdir)/git.mk
