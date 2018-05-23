icondir = join_paths(data_dir, 'icons')

install_data('icons/hicolor/16x16/apps/org.gnome.Boxes.png',
  install_dir: icondir,
)

install_data('icons/hicolor/24x24/apps/org.gnome.Boxes.png',
  install_dir: icondir,
)

install_data('icons/hicolor/symbolic/apps/org.gnome.Boxes-symbolic.svg',
  install_dir: icondir,
)
install_data('icons/hicolor/32x32/apps/org.gnome.Boxes.png',
  install_dir: icondir,
)

install_data('icons/hicolor/48x48/apps/org.gnome.Boxes.png',
  install_dir: icondir,
)

install_data('icons/hicolor/256x256/apps/org.gnome.Boxes.png',
  install_dir: icondir,
)


resource_files = files ('gnome-boxes.gresource.xml')
resources = gnome.compile_resources ('org.gnome.Boxes',
                                     resource_files,
                                     c_name: 'resources')

i18n.merge_file ('desktop-file',
  type: 'desktop',
  input: 'org.gnome.Boxes.desktop.in',
  output: 'org.gnome.Boxes.desktop',
  po_dir: po_dir,
  install: true,
  install_dir: join_paths (data_dir, 'applications')
)

dbus_conf = configuration_data ()
dbus_conf.set ('bindir', join_paths (get_option ('prefix'), get_option ('bindir')))
dbus_conf.set ('libexecdir', join_paths (get_option ('prefix'), get_option ('libexecdir')))
configure_file (
  input: 'org.gnome.Boxes.service.in',
  output: 'org.gnome.Boxes.service',
  configuration: dbus_conf,
  install: true,
  install_dir: join_paths (data_dir, 'dbus-1', 'services')
)

configure_file (
  input: 'org.gnome.Boxes.SearchProvider.service.in',
  output: 'org.gnome.Boxes.SearchProvider.service',
  configuration: dbus_conf,
  install: true,
  install_dir: join_paths (data_dir, 'dbus-1', 'services')
)

i18n.merge_file ('appdata-file',
  input: 'org.gnome.Boxes.appdata.xml.in',
  output: 'org.gnome.Boxes.appdata.xml',
  po_dir: po_dir,
  install: true,
  install_dir: join_paths (data_dir, 'metainfo')
)

gsettings_conf = configuration_data ()
gsettings_conf.set ('GETTEXT_PACKAGE', meson.project_name ())
configure_file (
  input: 'org.gnome.boxes.gschema.xml',
  output: 'org.gnome.boxes.gschema.xml',
  configuration: gsettings_conf,
  install: true,
  install_dir: join_paths(data_dir, 'glib-2.0', 'schemas'),
)

install_data ('gnome-boxes-search-provider.ini', install_dir : join_paths (data_dir, 'gnome-shell', 'search-providers'))
install_data ('QEMU_Session', install_dir : join_paths (data_dir, 'gnome-boxes/sources'))
install_data ('disk.img', install_dir : join_paths (data_dir, 'gnome-boxes/unattended'))

subdir ('osinfo')
