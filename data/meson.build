install_subdir('icons/hicolor/', install_dir: join_paths (data_dir, 'icons'))

resource_files = files ('gnome-boxes.gresource.xml')
resources = gnome.compile_resources ('org.gnome.Boxes',
                                     resource_files,
                                     c_name: 'resources')

custom_target ('desktop-file',
              input: files ('org.gnome.Boxes.desktop.in.in'),
              output: 'org.gnome.Boxes.desktop',
              install: true,
              install_dir: join_paths (data_dir, 'applications'),
              command: [msgfmt, '--desktop', '-d', '../po', '--template', '@INPUT@', '-o', '@OUTPUT@'])

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

custom_target ('appdata-file',
  input: 'org.gnome.Boxes.appdata.xml.in',
  output: 'org.gnome.Boxes.appdata.xml',
  install: true,
  install_dir: join_paths (data_dir, 'metainfo'),
  command: [ msgfmt, '--xml', '--template', '@INPUT@', '-d', po_dir, '-o', '@OUTPUT@' ],
)

configure_file (
  input: 'gnome-boxes-search-provider.ini.in',
  output: 'gnome-boxes-search-provider.ini',
  configuration: configuration_data (),
  install_dir: join_paths (data_dir, 'gnome-shell', 'search-providers'),
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

install_data ('QEMU_Session', install_dir : join_paths (data_dir, 'gnome-boxes/sources'))
install_data ('disk.img', install_dir : join_paths (data_dir, 'gnome-boxes/unattended'))

subdir ('osinfo')
