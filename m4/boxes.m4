AC_DEFUN([VALA_ADD_CHECKFILE],
[
    vala_checkfiles="$vala_checkfiles $srcdir/$1"
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
    dnl Enable check for Vala even if not asked to do so if checkfile files are absent.
    for checkfile in $vala_checkfiles
    do
        AS_IF([test ! -e "$checkfile"],
              [AC_MSG_WARN([Missing checkfile file $[]checkfile. Forcing vala mode])
               enable_vala=yes
              ])
    done

    dnl Vala
    AS_IF([test x$enable_vala = xyes],
          [
           dnl check for vala
           AM_PROG_VALAC([$1])
           AS_IF([test x$VALAC = "x"],
                 [AC_MSG_ERROR([Cannot find the "valac" compiler in your PATH])],
                 [VALA_CHECK_PACKAGES([$2])])

           dnl check for vapigen
           AC_PATH_PROG(VAPIGEN, vapigen, no)
           AS_IF([test x$VAPIGEN = "xno"],
                 [AC_MSG_ERROR([Cannot find the "vapigen compiler in your PATH])])

           ],
           []
    )
])
