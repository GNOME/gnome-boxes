AC_PREREQ([2.63])

AC_INIT([gnome-boxes],
        [m4_esyscmd(build-aux/git-version-gen .tarball-version)],
        [https://bugzilla.gnome.org/enter_bug.cgi?product=gnome-boxes],
        [gnome-boxes],
        [http://live.gnome.org/Boxes])

AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_AUX_DIR([build-aux])

AM_INIT_AUTOMAKE([1.11 dist-xz no-dist-gzip tar-ustar foreign -Wall -Werror])
AM_MAINTAINER_MODE([enable])

AM_SILENT_RULES([yes])

# Check for programs
AC_PROG_CC
AM_PROG_CC_C_O
AC_PROG_CXX
AM_PROG_VALAC([0.14.0])

# Initialize libtool
LT_PREREQ([2.2])
LT_INIT([disable-static])

# Pkg-config
PKG_PROG_PKG_CONFIG([0.22])

# i18 support
IT_PROG_INTLTOOL(0.40.0)

AM_GNU_GETTEXT([external])
AM_GNU_GETTEXT_VERSION([0.17])

GETTEXT_PACKAGE=AC_PACKAGE_NAME
AC_SUBST(GETTEXT_PACKAGE)
AC_DEFINE_UNQUOTED(GETTEXT_PACKAGE,"$GETTEXT_PACKAGE",[The name of the gettext domain])

# GObject-introspection support
GOBJECT_INTROSPECTION_REQUIRE([0.9.6])

# GSettings support
GLIB_GSETTINGS

CLUTTER_GTK_MIN_VERSION=1.0.1
GLIB_MIN_VERSION=2.29.90
GOBJECT_INTROSPECTION_MIN_VERSION=0.9.6
GTK_MIN_VERSION=3.3.5
GTK_VNC_MIN_VERSION=0.4.4
LIBVIRT_GLIB_MIN_VERSION=0.0.3
LIBVIRT_GCONFIG_MIN_VERSION=0.0.4
LIBXML2_MIN_VERSION=2.7.8
SPICE_GTK_MIN_VERSION=0.7.98
GUDEV_MIN_VERSION=147
OSINFO_MIN_VERSION=0.0.4

PKG_CHECK_MODULES(BOXES, [
  clutter-gtk-1.0 >= $CLUTTER_GTK_MIN_VERSION
  glib-2.0 >= $GLIB_MIN_VERSION
  gobject-introspection-1.0 >= $GOBJECT_INTROSPECTION_MIN_VERSION
  gtk+-3.0 >= $GTK_MIN_VERSION
  gtk-vnc-2.0 >= $GTK_VNC_MIN_VERSION
  libvirt-gobject-1.0 >= $LIBVIRT_GLIB_MIN_VERSION
  libvirt-gconfig-1.0 >= $LIBVIRT_GCONFIG_MIN_VERSION
  libxml-2.0 >= $LIBXML2_MIN_VERSION
  spice-client-gtk-3.0 >= $SPICE_GTK_MIN_VERSION
  gudev-1.0 >= $GUDEV_MIN_VERSION
  libosinfo-1.0 >= $OSINFO_MIN_VERSION
])

VALA_CHECK_PACKAGES([
  clutter-gtk-1.0
  cogl-1.0
  gdk-pixbuf-2.0
  glib-2.0
  gtk+-3.0
  gtk-vnc-2.0
  gudev-1.0
  libosinfo-1.0
  libvirt-gconfig-1.0
  libvirt-gobject-1.0
  libxml-2.0
  posix
  spice-client-gtk-3.0
])

dnl Strict compiler
AC_ARG_ENABLE([strict-cc],
  AS_HELP_STRING([--enable-strict-cc],[Enable strict C compiler]))

AS_IF([test "x$enable_strict_cc" = "xyes"], [CFLAGS="$CFLAGS -Wall -Werror"],
      [CFLAGS="$CFLAGS -w"])

AC_CONFIG_FILES([
  Makefile
  data/Makefile
  data/gnome-boxes.desktop.in
  data/icons/Makefile
  po/Makefile.in
  src/Makefile
  vapi/Makefile
  vapi/upstream/Makefile
])

AC_OUTPUT

dnl ==========================================================================
AC_MSG_NOTICE([

        GNOME Boxes $VERSION
        =================

        prefix:                   ${prefix}
        c compiler:               ${CC} ${CFLAGS}
])
