AC_PREREQ([2.63])

AC_INIT([gnome-boxes], [m4_esyscmd(build-aux/git-version-gen .tarball-version)],
        [spice-devel@lists.freedesktop.org])

AC_CONFIG_MACRO_DIR([m4])
AM_CONFIG_HEADER([config.h])
AC_CONFIG_AUX_DIR([build-aux])
m4_ifdef([AM_SILENT_RULES],[AM_SILENT_RULES([yes])])

AM_INIT_AUTOMAKE([1.11 dist-xz no-dist-gzip tar-ustar foreign -Wall -Werror])
LT_INIT
AM_MAINTAINER_MODE([enable])

GETTEXT_PACKAGE=AC_PACKAGE_NAME
AC_SUBST(GETTEXT_PACKAGE)
AC_DEFINE_UNQUOTED(GETTEXT_PACKAGE,"$GETTEXT_PACKAGE",[The name of the gettext domain])
IT_PROG_INTLTOOL(0.40.0)
PKG_PROG_PKG_CONFIG([0.22])

AM_GNU_GETTEXT([external])
AM_GNU_GETTEXT_VERSION([0.17])

GOBJECT_INTROSPECTION_REQUIRE([0.9.6])

AC_PROG_CC
AM_PROG_CC_C_O
AC_PROG_CXX
AM_PROG_VALAC([0.14.0])

# no stupid static libraries
AM_DISABLE_STATIC
AC_PROG_LIBTOOL

GJS_JS_DIR=`$PKG_CONFIG --variable=datadir gjs-1.0`/gjs-1.0
AC_SUBST(GJS_JS_DIR)

GLIB_GSETTINGS

GLIB_MIN_VERSION=2.29.90
GTK_MIN_VERSION=3.1.13
GOBJECT_INTROSPECTION_MIN_VERSION=0.9.6
CLUTTER_GTK_MIN_VERSION=1.0.1
SPICE_GTK_MIN_VERSION=0.7
LIBVIRT_GLIB_MIN_VERSION=0.0.1
LIBXML2_MIN_VERSION=2.7.8

PKG_CHECK_MODULES(BOXES, [
  clutter-gtk-1.0 >= $CLUTTER_GTK_MIN_VERSION
  glib-2.0 >= $GLIB_MIN_VERSION
  gobject-introspection-1.0 >= $GOBJECT_INTROSPECTION_MIN_VERSION
  spice-client-gtk-3.0 >= $SPICE_GTK_MIN_VERSION
  gtk+-3.0 >= $GTK_MIN_VERSION
  libvirt-gobject-1.0 >= $LIBVIRT_GLIB_MIN_VERSION
  libxml-2.0 >= $LIBXML2_MIN_VERSION
])

VALA_CHECK_PACKAGES([
  clutter-gtk-1.0
  gdk-pixbuf-2.0
  glib-2.0
  libxml-2.0
])

AC_CONFIG_FILES([
  Makefile
  src/Makefile
  data/Makefile
  data/gnome-boxes.desktop.in
  po/Makefile.in
])

AC_OUTPUT

dnl ==========================================================================
AC_MSG_NOTICE([

        Boxes $VERSION
        ==============

        prefix:                   ${prefix}
        c compiler:               ${CC}
])
