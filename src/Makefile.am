NULL =
BUILT_SOURCES =
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
	--pkg common					\
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

noinst_LIBRARIES = libcommon.a
libcommon_a_VALASOURCES =			\
	collection-source.vala			\
	display-config.vala			\
	display-properties.vala			\
	util.vala				\
	$(NULL)

libcommon_a_DEPENDENCIES =			\
	common.vapi				\
	libcommon.h				\
	libcommon_vala.stamp			\
	$(NULL)

libcommon_a_SOURCES =				\
	$(libcommon_a_VALASOURCES:.vala=.c)	\
	$(NULL)

libcommon_a_CFLAGS = $(BOXES_COMMON_CFLAGS)

libcommon_vala.stamp common.vapi: $(libcommon_a_VALASOURCES)
	$(AM_V_VALAC)$(VALAC) $(VALAFLAGS) $(VALA_DEBUG_FLAGS)	\
	--enable-experimental					\
	--vapidir=$(srcdir)/					\
	--pkg config						\
	--pkg glib-2.0						\
	--pkg gio-2.0						\
	-C -H libcommon.h --library common $^
	@touch $(libcommon_a_DEPENDENCIES)

BUILT_SOURCES += $(libcommon_a_DEPENDENCIES)
MAINTAINERCLEANFILES += $(libcommon_a_SOURCES) $(libcommon_a_DEPENDENCIES)

bin_PROGRAMS = gnome-boxes

gnome_boxes_SOURCES =				\
	app.vala				\
	collection-view.vala			\
	collection.vala				\
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

gnome_boxes_LDADD =					\
	$(BOXES_LIBS)					\
	$(top_builddir)/libgd/libgdprivate-1.0.la	\
	libcommon.a					\
	$(NULL)

gnome_boxes_CFLAGS = $(BOXES_CFLAGS)

MAINTAINERCLEANFILES += $(gnome_boxes_SOURCES:.vala=.c)

libexec_PROGRAMS = gnome-boxes-search-provider

gnome_boxes_search_provider_SOURCES =		\
	gnome-boxes-search-provider.vala	\
	$(NULL)

gnome_boxes_search_provider_LDADD = $(BOXES_COMMON_LIBS) libcommon.a
gnome_boxes_search_provider_CFLAGS = $(BOXES_COMMON_CFLAGS)

MAINTAINERCLEANFILES += $(gnome_boxes_search_provider_SOURCES:.vala=.c)

EXTRA_DIST = config.vapi

-include $(top_srcdir)/git.mk
