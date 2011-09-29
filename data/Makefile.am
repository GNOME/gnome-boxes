NULL=

desktopdir       = $(datadir)/applications
desktop_in_files = boxes.desktop.in
desktop_DATA     = $(desktop_in_files:.desktop.in=.desktop)
@INTLTOOL_DESKTOP_RULE@

EXTRA_DIST =					\
	boxes.desktop.in			\
	$(desktop_in_files)			\
	$(NULL)

CLEANFILES =					\
	$(desktop_DATA)				\
	$(NULL)

DISTCLEANFILES =				\
	$(desktop_DATA)				\
	$(NULL)

-include $(top_srcdir)/git.mk
