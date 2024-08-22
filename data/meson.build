icondir = join_paths('icons', 'hicolor', 'scalable', 'apps')
install_data(
  join_paths(icondir, ('@0@.svg').format(application_id)),
  install_dir: join_paths(data_dir, icondir),
  rename: '@0@.svg'.format(application_id)
)

icondir = join_paths('icons', 'hicolor', 'symbolic', 'apps')
install_data(
  join_paths(icondir, 'org.gnome.Boxes-symbolic.svg'),
  install_dir: join_paths(data_dir, icondir),
  rename: '@0@-symbolic.svg'.format(application_id)
)

resource_files = files ('gnome-boxes.gresource.xml')
resources = gnome.compile_resources ('org.gnome.Boxes',
                                     resource_files,
                                     c_name: 'resources')

desktop_conf = configuration_data ()
desktop_conf.set ('icon', application_id)
desktop = i18n.merge_file (
  input: configure_file (
    input: files ('org.gnome.Boxes.desktop.in'),
    output: 'org.gnome.Boxes.desktop.in',
    configuration: desktop_conf
  ),
  output: '@0@.desktop'.format(application_id),
  install: true,
  install_dir: join_paths (data_dir, 'applications'),
  po_dir: po_dir,
  type: 'desktop'
)
desktop_file_validate = find_program ('desktop-file-validate', required: false)
if desktop_file_validate.found()
  test(
    'validate-desktop',
    desktop_file_validate,
    args: [
      desktop.full_path()
    ]
  )
endif

dbus_conf = configuration_data ()
dbus_conf.set ('bindir', join_paths (get_option ('prefix'), get_option ('bindir')))
dbus_conf.set ('libexecdir', join_paths (get_option ('prefix'), get_option ('libexecdir')))
dbus_conf.set ('appid', application_id)
configure_file (
  input: 'org.gnome.Boxes.service.in',
  output: '@0@.service'.format (application_id),
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

metainfo_conf = configuration_data()
metainfo_conf.set('appid', application_id)
metainfo_file = i18n.merge_file (
  input: configure_file (
    input: files ('org.gnome.Boxes.metainfo.xml.in'),
    output: 'org.gnome.Boxes.metainfo.xml.in',
    configuration: metainfo_conf
  ),
  output: '@0@.metainfo.xml'.format (application_id),
  po_dir: po_dir,
  install: true,
  install_dir: join_paths (data_dir, 'metainfo')
)
appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test(
    'validate-metainfo', appstreamcli,
    args: [
      'validate', '--no-net', '--explain', metainfo_file.full_path()
    ]
  )
endif

gsettings_conf = configuration_data ()
gsettings_conf.set ('GETTEXT_PACKAGE', meson.project_name ())
configure_file (
  input: 'org.gnome.boxes.gschema.xml',
  output: 'org.gnome.boxes.gschema.xml',
  configuration: gsettings_conf,
  install: true,
  install_dir: join_paths(data_dir, 'glib-2.0', 'schemas'),
)

search_provider_conf = configuration_data()
search_provider_conf.set ('appid', application_id)
search_provider_conf.set ('profile', profile)
configure_file (
  configuration: search_provider_conf,
  input: files ('gnome-boxes-search-provider.ini'),
  install_dir: join_paths (data_dir, 'gnome-shell', 'search-providers'),
  output: '@0@.SearchProvider.ini'.format (application_id)
)

install_data ('QEMU_Session', install_dir : join_paths (data_dir, 'gnome-boxes/sources'))
install_data ('disk.img', install_dir : join_paths (data_dir, 'gnome-boxes/unattended'))

subdir ('osinfo')
