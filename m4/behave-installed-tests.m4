# How to use the installed tests m4
#
#   Place BEHAVE_INSTALLED_TESTS somewhere in configure.ac
#
#   Writing your Makefile.am
#   ~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Somewhere in your Makefile.am in this test directory, you need to declare
#   the following variables:
#
#       INSTALLED_TESTS=list of tags for tests to install
#       INSTALLED_TESTS_TYPE=session-exclusive
#
#   First the list of tests which should be installed, followed by
#   the type of test they should be configured as. The type can
#   be 'session' or 'session-exclusive'
#
#   More information about valid types can be found here:
#      https://wiki.gnome.org/GnomeGoals/InstalledTests
#
#   The last variable is optional, but can be useful to configure
#   your test program to run in the installed environment as opposed
#   to the normal `make check' run.
#
#   Then place this somewhere in your Makefile.am
#
#       @BEHAVE_INSTALLED_TESTS_RULE@
#
#   And the following in configure.ac
#
#       BEHAVE_INSTALLED_TESTS
#
#   And that's it, now your unit tests will be installed along with
#   a .test metadata file into $(pkglibexecdir) if --enable-installed-tests
#   is passed to your configure script, and will be run automatically
#   by the continuous integration servers.
#
#   FIXME: Change the above link to point to real documentation, not
#   a gnome goal page which might disappear at some point.
#
# BUGS: This macro hooks into install-exec-am and install-data-am
# which are internals of Automake. This is because Automake doesnt
# consider the regular install-exec-local / install-exec-hook or
# data install components unless variables have been setup for them
# in advance.
#
# This doesnt seem to present a problem, but it is depending on
# internals of Automake instead of clear documented API.

# Place this in configure.ac to enable
# the installed tests option.

AC_DEFUN([BEHAVE_INSTALLED_TESTS], [
AC_PREREQ([2.50])dnl
AC_REQUIRE([AM_NLS])dnl

  AC_PROG_INSTALL
  AC_PROG_MKDIR_P
  AC_PROG_LIBTOOL

  AC_ARG_ENABLE(installed-tests,
		[AC_HELP_STRING([--enable-installed-tests],
				[enable installed unit tests [default=no]])],,
		[enable_installed_tests="no"])

  AM_CONDITIONAL([BEHAVE_INSTALLED_TESTS_ENABLED],[test "x$enable_installed_tests" = "xyes"])
  AC_SUBST([BEHAVE_INSTALLED_TESTS_ENABLED], [$enable_installed_tests])

  # Define the rule for makefiles
  BEHAVE_INSTALLED_TESTS_RULE='

ifeq ($(BEHAVE_INSTALLED_TESTS_ENABLED),yes)

install-exec-am: installed-tests-exec-hook
install-data-am: installed-tests-data-hook
uninstall-am: uninstall-tests-hook

META_DIRECTORY=${DESTDIR}${datadir}/installed-tests/${PACKAGE}
EXEC_DIRECTORY=${DESTDIR}${pkglibexecdir}/installed-tests

BEHAVE_FEATURES=$(wildcard $(srcdir)/tests/*.feature)
BEHAVE_STEP_DEFINITION=$(wildcard $(srcdir)/tests/steps/*.py)
BEHAVE_COMMON_FILES=$(srcdir)/tests/environment.py $(srcdir)/tests/common_steps.py

FINAL_TEST_ENVIRONMENT=
ifneq ($(INSTALLED_TESTS_ENVIRONMENT),)
      FINAL_TEST_ENVIRONMENT="env $(INSTALLED_TESTS_ENVIRONMENT)"
endif

installed-tests-exec-hook:
	@$(MKDIR_P) $(EXEC_DIRECTORY);
	@for feature in $(BEHAVE_FEATURES); do											\
	    $(LIBTOOL) --mode=install $(INSTALL) --mode=777 $$feature $(EXEC_DIRECTORY);\
	done
	@for common_file in $(BEHAVE_COMMON_FILES); do										\
	    $(LIBTOOL) --mode=install $(INSTALL) --mode=777 $$common_file $(EXEC_DIRECTORY);\
	done
	@$(MKDIR_P) $(EXEC_DIRECTORY)/steps;
	@for step_definition in $(BEHAVE_STEP_DEFINITION); do									\
	    $(LIBTOOL) --mode=install $(INSTALL) --mode=777 $$step_definition $(EXEC_DIRECTORY)/steps;\
	done


installed-tests-data-hook:
	@$(MKDIR_P) $(META_DIRECTORY);
	@for test in $(INSTALLED_TESTS); do							\
	    echo "Installing $$test.test to $(META_DIRECTORY)";					\
	    echo m4_escape([[Test]]) > $(META_DIRECTORY)/$$test.test;				\
	    echo "Exec=behave $(pkglibexecdir)/installed-tests -i $$test -k -f html -o $$test.html -f plain"	\
	                                           >> $(META_DIRECTORY)/$$test.test;		\
	    echo "Type=$(INSTALLED_TESTS_TYPE)" >> $(META_DIRECTORY)/$$test.test;		\
	done

uninstall-tests-hook:
	@for feature in $(BEHAVE_FEATURES); do\
	    echo "Removing feature $(EXEC_DIRECTORY) $$feature";\
	    $(LIBTOOL) --mode=uninstall $(RM) $(EXEC_DIRECTORY)/$$feature;\
	done
	@for common_file in $(BEHAVE_COMMON_FILES); do\
	    echo "Removing feature $(EXEC_DIRECTORY) $$common_file";\
	    $(LIBTOOL) --mode=uninstall $(RM) $(EXEC_DIRECTORY)/$$common_file;\
	done
	@for step_definition in $(BEHAVE_STEP_DEFINITION); do\
	    echo "Removing feature $(EXEC_DIRECTORY)/steps $$step_definition";\
	    $(LIBTOOL) --mode=uninstall $(RM) $(EXEC_DIRECTORY)/steps/$$step_definition;\
	done
	@for test in $(INSTALLED_TESTS); do\
	    $(LIBTOOL) --mode=uninstall $(RM) $(META_DIRECTORY)/$$test.test;\
	done

endif
'

  # substitute @BEHAVE_INSTALLED_TESTS_RULE@ in Makefiles
  AC_SUBST([BEHAVE_INSTALLED_TESTS_RULE])
  m4_ifdef([_AM_SUBST_NOTMAKE], [_AM_SUBST_NOTMAKE([BEHAVE_INSTALLED_TESTS_RULE])])
])
