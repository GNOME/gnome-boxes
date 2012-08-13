NULL =
MAINTAINERCLEANFILES = *.stamp

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
	--vapidir=$(top_srcdir)/libgd                   \
	--vapidir=$(top_srcdir)/vapi                    \
	--vapidir=$(top_srcdir)/vapi/upstream           \
	--pkg clutter-gtk-1.0				\
	--pkg cogl-1.0					\
	--pkg config					\
	--pkg gd-1.0					\
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
	--pkg tracker-sparql-0.14			\
	$(VALA_DEBUG_FLAGS)			        \
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
	i-properties-provider.vala		\
	installer-media.vala 			\
	libvirt-machine.vala			\
	machine.vala				\
	main.vala				\
	media-manager.vala 			\
	mini-graph.vala				\
	notificationbar.vala			\
	os-database.vala 			\
	properties.vala				\
	remote-machine.vala			\
	revealer.vala				\
	searchbar.vala				\
	selectionbar.vala			\
	sidebar.vala				\
	spice-display.vala			\
	topbar.vala				\
	ui.vala					\
	unattended-installer.vala 		\
	util.vala				\
	util-app.vala				\
	vm-configurator.vala 			\
	vm-creator.vala 			\
	vnc-display.vala			\
	win7-installer.vala 			\
	windows-installer.vala 			\
	winxp-installer.vala 			\
	wizard-source.vala			\
	wizard.vala				\
	$(NULL)

gnome_boxes_LDADD = $(BOXES_LIBS) $(top_builddir)/libgd/libgdprivate-1.0.la
gnome_boxes_CFLAGS = $(BOXES_CFLAGS)

MAINTAINERCLEANFILES += $(gnome_boxes_SOURCES:.vala=.c)

EXTRA_DIST = config.vapi

-include $(top_srcdir)/git.mk
