project ('gnome-boxes',
         ['vala', 'c'],
         version: '3.28.5',
         license: 'LGPLv2+',
         meson_version: '>= 0.43',
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

conf = configuration_data ()
conf.set_quoted ('DISTRIBUTOR_NAME', get_option ('distributor_name'))
conf.set_quoted ('DISTRIBUTOR_VERSION', get_option ('distributor_version'))
conf.set_quoted ('PACKAGE_NAME', meson.project_name ())
conf.set_quoted ('PACKAGE_TARNAME', meson.project_name ())
conf.set_quoted ('PACKAGE_VERSION', meson.project_version ())
conf.set_quoted ('GETTEXT_PACKAGE', meson.project_name ())
conf.set('PACKAGE_URL', '"https://wiki.gnome.org/Apps/Boxes"')
conf.set_quoted ('DATADIR', data_dir)
conf.set_quoted ('CACHEDIR', '/var/cache')
conf.set_quoted ('LOCALEDIR', locale_dir)
conf.set('PACKAGE_BUGREPORT', '"http://gitlab.gnome.org/gnome/gnome-boxes/issues"')

configure_file (output: 'config.h', configuration: conf)
config_h_dir = include_directories ('.')

meson.add_install_script (join_paths ('build-aux', 'post_install.py'), data_dir)

subdir ('data')
subdir ('help')
subdir ('po')
subdir ('src')

if get_option ('installed_tests')
  subdir ('tests')
endif
