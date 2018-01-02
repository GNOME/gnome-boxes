NULL=
SUBDIRS = icons osinfo

desktopdir       = $(datadir)/applications
desktop_in_files = org.gnome.Boxes.desktop.in
desktop_DATA     = $(desktop_in_files:.desktop.in=.desktop)

$(desktop_DATA): %.desktop: %.desktop.in
	$(AM_V_GEN)$(MSGFMT) --desktop --template $< -d $(top_srcdir)/po -o $@

all-local: $(desktop_DATA)
	@$(DESKTOP_FILE_VALIDATE) $(desktop_DATA)

gsettings_SCHEMAS = org.gnome.boxes.gschema.xml
@GSETTINGS_RULES@

appdatadir = $(datadir)/metainfo
appdata_in_file = org.gnome.Boxes.appdata.xml.in
appdata_DATA = $(appdata_in_file:.xml.in=.xml)

$(appdata_DATA): $(appdata_in_file)
	$(AM_V_GEN)$(MSGFMT) --xml --template $< -d $(top_srcdir)/po -o $@

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
	gnome-boxes-search-provider.ini		\
	org.gnome.Boxes.service.in	\
	$(gresource_file)			\
	$(gsettings_SCHEMAS)			\
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
	$(service_DATA)				\
	$(desktop_DATA)				\
	$(appdata_DATA)				\
	$(NULL)

MAINTAINERCLEANFILES =				\
	org.gnome.boxes.gschema.valid		\
	$(NULL)

org.gnome.Boxes.SearchProvider.service: org.gnome.Boxes.SearchProvider.service.in Makefile
	$(AM_V_GEN) [ -d $(@D) ] || $(mkdir_p) $(@D) ; \
	            sed -e "s|\@libexecdir\@|$(libexecdir)|" $< > $@.tmp && mv $@.tmp $@

-include $(top_srcdir)/git.mk
