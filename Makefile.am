ACLOCAL_AMFLAGS = -I m4
NULL =

SUBDIRS = data src po

INTLTOOL_FILES =				\
	intltool-extract.in			\
	intltool-merge.in			\
	intltool-update.in			\
	$(NULL)

DISTCLEANFILES =				\
	intltool-extract			\
	intltool-merge				\
	intltool-update				\
	gnome-doc-utils.make			\
	po/.intltool-merge-cache		\
	$(NULL)

EXTRA_DIST =					\
	build-aux/git-version-gen		\
	.version				\
	$(INTLTOOL_FILES)			\
	$(NULL)

MAINTAINERCLEANFILES =				\
	ABOUT-NLS				\
	aclocal.m4				\
	config.h.in				\
	m4/*.m4					\
	build-aux/compile			\
	build-aux/config.guess			\
	build-aux/config.rpath			\
	build-aux/config.sub			\
	build-aux/depcomp			\
	build-aux/install-sh			\
	build-aux/ltmain.sh			\
	build-aux/missing			\
	build-aux/mkinstalldirs			\
	po/Makefile.in.in			\
	$(NULL)

# see git-version-gen
dist-hook:
	echo $(VERSION) > $(distdir)/.tarball-version

BUILT_SOURCES = $(top_srcdir)/.version
$(top_srcdir)/.version:
	echo $(VERSION) > $@-t && mv $@-t $@

all: version.h

version.h: $(top_srcdir)/.version
	echo '#define BUILD_VERSION "'`cat $(top_srcdir)/.version`'"' > $@-t && mv $@-t $@

-include $(top_srcdir)/git.mk
