ACLOCAL_AMFLAGS = -I m4 -I libgd ${ACLOCAL_FLAGS}
NULL =

SUBDIRS = data help libgd src po vapi

INTLTOOL_FILES =				\
	intltool-extract.in			\
	intltool-merge.in			\
	intltool-update.in			\
	$(NULL)

DISTCLEANFILES =				\
	intltool-extract			\
	intltool-merge				\
	intltool-update				\
	po/.intltool-merge-cache		\
	$(NULL)

EXTRA_DIST =					\
	CodingStyle.txt				\
	THANKS					\
	HACKING					\
	build-aux/git-version-gen		\
	m4/boxes.m4				\
	.version				\
	$(INTLTOOL_FILES)			\
	$(NULL)

MAINTAINERCLEANFILES =				\
	ABOUT-NLS				\
	aclocal.m4				\
	config.h.in				\
	build-aux/ar-lib			\
	build-aux/compile			\
	build-aux/config.guess			\
	build-aux/config.rpath			\
	build-aux/config.sub			\
	build-aux/depcomp			\
	build-aux/install-sh			\
	build-aux/ltmain.sh			\
	build-aux/missing			\
	build-aux/mkinstalldirs			\
	m4/intltool.m4				\
	m4/libtool.m4				\
	m4/ltoptions.m4				\
	m4/ltsugar.m4				\
	m4/ltversion.m4				\
	m4/lt~obsolete.m4			\
	po/Makefile.in.in			\
	po/Makevars.template			\
	po/Rules-quot				\
	po/boldquot.sed				\
	po/en@boldquot.header			\
	po/en@quot.header			\
	po/insert-header.sin			\
	po/quot.sed				\
	po/remove-potcdate.sin			\
	$(NULL)

# see git-version-gen
dist-hook:
	echo $(VERSION) > $(distdir)/.tarball-version

BUILT_SOURCES = $(top_srcdir)/.version
$(top_srcdir)/.version:
	echo $(VERSION) > $@-t && mv $@-t $@

all:

vala-clean:
	rm -f `find . -name "*.stamp"`

win-tools.iso:
	@wget -O $@ http://people.gnome.org/~teuf/gnome-boxes/boxes-unattended-win-drivers/boxes-unattended-win-drivers-LATEST.iso

@BEHAVE_INSTALLED_TESTS_RULE@
INSTALLED_TESTS=				\
	general.feature				\
	import-vms.feature			\
	livecd.feature				\
	multi-windows.feature			\
	snapshots.feature			\
	spice.feature				\
	$(NULL)
INSTALLED_TESTS_TYPE=session-exclusive
-include $(top_srcdir)/git.mk
