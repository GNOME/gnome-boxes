project ('gnome-boxes',
         ['vala', 'c'],
         version: '49.0',
         license: 'LGPLv2+',
         meson_version: '>= 0.59.0',
)

gnome = import ('gnome')
i18n = import ('i18n')

cc = meson.get_compiler ('c')
valac = meson.get_compiler ('vala')

libarchive_dep = dependency ('libarchive', version: '>= 3.0.0')

src_dir = join_paths (meson.source_root (), 'src')
vapi_dir = join_paths (meson.source_root (), 'vapi')

config_dep = valac.find_library ('config', dirs: src_dir)

pkglibdir = join_paths (get_option ('libdir'), meson.project_name ())

po_dir = join_paths (meson.source_root (), 'po')
data_dir = join_paths (get_option ('prefix'), get_option ('datadir'))
locale_dir = join_paths (get_option ('prefix'), get_option ('localedir'))
pkgdatadir = join_paths (data_dir, meson.project_name ())

conf = configuration_data ()
conf.set_quoted ('DISTRIBUTOR_NAME', get_option ('distributor_name'))
conf.set_quoted ('DISTRIBUTOR_VERSION', get_option ('distributor_version'))
conf.set_quoted ('PACKAGE_NAME', meson.project_name ())
conf.set_quoted ('PACKAGE_TARNAME', meson.project_name ())
conf.set_quoted ('PACKAGE_VERSION', meson.project_version ())
conf.set_quoted ('GETTEXT_PACKAGE', meson.project_name ())
conf.set('PACKAGE_URL', '"https://gnomeboxes.org"')
conf.set_quoted ('DATADIR', data_dir)
conf.set_quoted ('CACHEDIR', '/var/cache')
conf.set_quoted ('LOCALEDIR', locale_dir)
conf.set10 ('UEFI_INSTALLS_SUPPORTED', get_option ('uefi'))
conf.set('PACKAGE_BUGREPORT', '"http://gitlab.gnome.org/gnome/gnome-boxes/issues"')

if get_option ('profile') == 'development'
  profile = 'Devel'
  name_suffix = ' (Development Snapshot)'
else
  profile = ''
  name_suffix = ''
endif

application_id = 'org.gnome.Boxes@0@'.format (profile)
conf.set_quoted ('PROFILE', profile)
conf.set_quoted ('APPLICATION_ID', application_id)
conf.set_quoted ('NAME_SUFFIX', name_suffix)
conf.set_quoted ('VERSION', '@0@-@VCS_TAG@'.format (meson.project_version()))

config_h = declare_dependency (
  sources: vcs_tag (
    command: ['git', 'rev-parse', '--short', 'HEAD'],
    fallback: get_option('profile') != 'default'? 'devel' : 'stable',
    input: configure_file (
      output: 'config.h.in',
      configuration: conf
    ),
    output: 'config.h'

  )
)

#configure_file (output: 'config.h', configuration: conf)
config_h_dir = include_directories ('.')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)

subdir ('data')
subdir ('help')
subdir ('po')
subdir ('src')

if get_option ('installed_tests')
  subdir ('tests')
endif