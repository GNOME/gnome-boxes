NULL =

gdprivate_cflags =				\
	-I$(top_srcdir)				\
	-DPREFIX=\"$(prefix)\"			\
	-DLIBDIR=\"$(libdir)\"			\
	-DG_LOG_DOMAIN=\"Gdprivate\"		\
	-DG_DISABLE_DEPRECATED			\
	$(LIBGD_CFLAGS)				\
	$(NULL)

gdprivate_source_h =				\
	gd.h					\
	gd-entry-focus-hack.h			\
	gd-margin-container.h			\
	gd-tagged-entry.h			\
	$(NULL)

gdprivate_source_c =				\
	gd-entry-focus-hack.c			\
	gd-margin-container.c			\
	gd-tagged-entry.c			\
	$(NULL)

pkglib_LTLIBRARIES = libgdprivate-1.0.la

libgdprivate_1_0_la_LIBADD =			\
	$(LIBGD_LIBS)				\
	$(LIBM)					\
	$(NULL)

libgdprivate_1_0_la_LDFLAGS =			\
	-avoid-version

libgdprivate_1_0_la_CPPFLAGS =			\
	$(gdprivate_cflags)

libgdprivate_1_0_la_SOURCES =			\
	$(gdprivate_source_h)			\
	$(gdprivate_source_c)			\
	$(NULL)

include $(INTROSPECTION_MAKEFILE)

INTROSPECTION_GIRS = Gd-1.0.gir

Gd-1.0.gir: libgdprivate-1.0.la Makefile
Gd_1_0_gir_NAMESPACE = Gd
Gd_1_0_gir_VERSION = 1.0
Gd_1_0_gir_LIBS = libgdprivate-1.0.la
Gd_1_0_gir_CFLAGS = $(AM_CPPFLAGS) $(gdprivate_cflags)
Gd_1_0_gir_SCANNERFLAGS =				\
	--warn-all					\
	--symbol-prefix=gd				\
	--identifier-prefix=Gd				\
        --c-include="libgd/gd.h"			\
	$(NULL)

Gd_1_0_gir_INCLUDES =				\
	Gtk-3.0					\
	$(NULL)

Gd_1_0_gir_FILES =				\
	$(gdprivate_source_h:%=$(srcdir)/%)	\
	$(gdprivate_source_c:%=$(srcdir)/%)	\
	$(NULL)
