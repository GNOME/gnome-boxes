AC_DEFUN([VALA_ADD_STAMP],
[
    vala_stamp_files="$vala_stamp_files $srcdir/$1"
])

AC_DEFUN([VALA_ADD_VALAFLAGS],
[
    VALAFLAGS="${VALAFLAGS:+$VALAFLAGS }$1"
])

AC_DEFUN([VALA_CHECK],
[
    AC_ARG_ENABLE([vala],
        [AS_HELP_STRING([--enable-vala],[enable checks for vala])],,
            [enable_vala=no])
    AC_ARG_ENABLE([vala-fatal-warnings],
        [AS_HELP_STRING([--enabla-vala-fatal-warnings],[Treat vala warnings as fatal])],,
            [enable_vala_fatal_warnings=no])
    AS_IF([test "x$enable_vala_fatal_warnings" = "xyes"],
          [VALA_ADD_VALAFLAGS([--fatal-warnings])])
    AC_SUBST([VALAFLAGS])
    dnl Enable check for Vala even if not asked to do so if stamp files are absent.
    for stamp in $vala_stamp_files
    do
        AS_IF([test ! -e "$stamp"],
              [AC_MSG_WARN([Missing stamp file $[]stamp. Forcing vala mode])
               enable_vala=yes
              ])
    done

    dnl Vala
    AS_IF([test x$enable_vala = xyes],
          [dnl check for vala
           AM_PROG_VALAC([$1])

           AS_IF([test x$VALAC = "x"],
                 [AC_MSG_ERROR([Cannot find the "valac" compiler in your PATH])],
                 [VALA_CHECK_PACKAGES([$2])])
           ],
           []
    )
])

