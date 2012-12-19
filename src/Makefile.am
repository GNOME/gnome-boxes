NULL =
BUILT_SOURCES =
EXTRA_DIST =
MAINTAINERCLEANFILES = *.stamp

AM_CPPFLAGS =						\
	-include config.h				\
	-DGNOMELOCALEDIR=\""$(datadir)/locale"\"	\
	-DDATADIR=\""$(datadir)"\"			\
	$(DISABLE_DEPRECATED)				\
	-DG_LOG_DOMAIN=\""Boxes"\"			\
	-I$(top_srcdir)/libgd                           \
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
	--pkg gio-2.0-workaround			\
	--pkg glib-2.0					\
	--pkg gtk-vnc-2.0				\
	--pkg gudev-1.0					\
	--pkg libsoup-2.4             			\
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
	box-config.vala                         \
	collection-source.vala			\
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

libcommon_vala.stamp: $(libcommon_a_VALASOURCES)
	$(AM_V_VALAC)$(VALAC) $(VALAFLAGS) $(VALA_DEBUG_FLAGS)	\
	--enable-experimental					\
	--vapidir=$(srcdir)/					\
	--pkg config						\
	--pkg glib-2.0						\
	--pkg gio-2.0						\
	-C -H libcommon.h --library common $^
	@touch $(libcommon_a_DEPENDENCIES)

common.vapi libcommon.h: libcommon_vala.stamp
$(libcommon_a_SOURCES): libcommon_vala.stamp

MAINTAINERCLEANFILES += $(libcommon_a_SOURCES) $(libcommon_a_DEPENDENCIES)
EXTRA_DIST += $(libcommon_a_DEPENDENCIES) $(libcommon_a_VALASOURCES)

bin_PROGRAMS = gnome-boxes

gnome_boxes_SOURCES =				\
	clutter-widget.vala			\
	app.vala				\
	collection-view.vala			\
	collection.vala				\
	display-page.vala			\
	display.vala				\
	editable-entry.vala			\
	i-properties-provider.vala		\
	installer-media.vala 			\
	iso-extractor.vala			\
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
	unattended-file.vala 			\
	util-app.vala				\
	vm-configurator.vala 			\
	vm-creator.vala 			\
	vnc-display.vala			\
	wizard-source.vala			\
	wizard.vala				\
	downloader.vala				\
	$(NULL)

gnome_boxes_LDADD =				\
	$(BOXES_LIBS)				\
	$(top_builddir)/libgd/libgd.la		\
	libcommon.a				\
	$(NULL)

gnome_boxes_CFLAGS = $(BOXES_CFLAGS)
$(srcdir)/gnome_boxes_vala.stamp: $(libcommon_a_DEPENDENCIES)

MAINTAINERCLEANFILES += $(gnome_boxes_SOURCES:.vala=.c)

libexec_PROGRAMS = gnome-boxes-search-provider

gnome_boxes_search_provider_SOURCES =		\
	gnome-boxes-search-provider.vala	\
	$(NULL)

gnome_boxes_search_provider_LDADD = $(BOXES_COMMON_LIBS) libcommon.a
gnome_boxes_search_provider_CFLAGS = $(BOXES_COMMON_CFLAGS)
$(srcdir)/gnome_boxes_search_provider_vala.stamp: $(libcommon_a_DEPENDENCIES)

MAINTAINERCLEANFILES += $(gnome_boxes_search_provider_SOURCES:.vala=.c)

EXTRA_DIST += config.vapi

-include $(top_srcdir)/git.mk
