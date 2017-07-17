NULL=
SUBDIRS = icons osinfo

desktopdir       = $(datadir)/applications
desktop_in_files = org.gnome.Boxes.desktop.in
desktop_DATA     = $(desktop_in_files:.desktop.in=.desktop)
@INTLTOOL_DESKTOP_RULE@

all-local: $(desktop_DATA)
	@$(DESKTOP_FILE_VALIDATE) $(desktop_DATA)

gsettings_SCHEMAS = org.gnome.boxes.gschema.xml
@INTLTOOL_XML_NOMERGE_RULE@
@GSETTINGS_RULES@

appdatadir = $(datadir)/appdata
appdata_in_file = org.gnome.Boxes.appdata.xml.in
appdata_DATA = $(appdata_in_file:.xml.in=.xml)
@INTLTOOL_XML_RULE@

sourcedir         = $(datadir)/gnome-boxes/sources
source_DATA       = QEMU_Session

iconsdir = $(pkgdatadir)/icons

searchproviderdir = $(datadir)/gnome-shell/search-providers
searchprovider_DATA = gnome-boxes-search-provider.ini

service_in_files = org.gnome.Boxes.SearchProvider.service.in

servicedir = $(datadir)/dbus-1/services
service_DATA = $(service_in_files:.service.in=.service)

unattendeddir = $(datadir)/gnome-boxes/unattended
unattended_DATA = disk.img			\
		  $(NULL)

disk.img:
	rm -f disk.img && qemu-img create -f raw disk.img 1440k && mkfs.msdos -s 1 disk.img

gresource_file = gnome-boxes.gresource.xml
resource_files = $(shell $(GLIB_COMPILE_RESOURCES) --generate-dependencies $(gresource_file))

dbusservicedir = $(datadir)/dbus-1/services
dbusservice_DATA = org.gnome.Boxes.service

org.gnome.Boxes.service: org.gnome.Boxes.service.in Makefile
		$(AM_V_GEN)$(SED) -e "s|[@]bindir[@]|$(bindir)|" $< > $@

EXTRA_DIST =					\
	org.gnome.Boxes.desktop.in		\
	gnome-boxes-search-provider.ini.in      \
	org.gnome.boxes.gschema.xml.in		\
	org.gnome.Boxes.service.in	\
	$(gresource_file)			\
	$(resource_files)			\
	$(desktop_in_files)			\
	$(source_DATA)				\
	$(unattended_DATA)			\
	$(searchprovider_DATA)			\
	$(service_in_files)			\
	$(appdata_in_file)			\
	$(NULL)

CLEANFILES =					\
	$(dbusservice_DATA)			\
	$(NULL)

DISTCLEANFILES =				\
	$(gsettings_SCHEMAS)			\
	$(service_DATA)				\
	$(desktop_DATA)				\
	$(appdata_DATA)				\
	$(NULL)

MAINTAINERCLEANFILES =				\
	gnome-boxes-search-provider.ini		\
	org.gnome.boxes.gschema.valid		\
	$(NULL)

gnome-boxes-search-provider.ini: gnome-boxes-search-provider.ini.in
	LC_ALL=C $(INTLTOOL_MERGE) -d -u -c $(top_builddir)/po/.intltool-merge-cache $(top_srcdir)/po $< $@

org.gnome.Boxes.SearchProvider.service: org.gnome.Boxes.SearchProvider.service.in Makefile
	$(AM_V_GEN) [ -d $(@D) ] || $(mkdir_p) $(@D) ; \
	            sed -e "s|\@libexecdir\@|$(libexecdir)|" $< > $@.tmp && mv $@.tmp $@

-include $(top_srcdir)/git.mk
