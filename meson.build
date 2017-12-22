project ('gnome-boxes',
         ['vala', 'c'],
         version: '3.25.3',
         license: 'LGPLv2+',
         meson_version: '>= 0.43',
)

gnome = import ('gnome')
i18n = import ('i18n')

cc = meson.get_compiler ('c')
valac = meson.get_compiler ('vala')

govirt_dep = dependency ('govirt-1.0', version: '>= 0.3.4')
libarchive_dep = dependency ('libarchive', version: '>= 3.0.0')

src_dir = join_paths (meson.source_root (), 'src')
vapi_dir = join_paths (meson.source_root (), 'vapi')

config_dep = valac.find_library ('config', dirs: src_dir)

pkglibdir = join_paths (get_option ('libdir'), meson.project_name ())
libgd = subproject (
  'libgd',
  default_options: [
    'pkglibdir=' + pkglibdir,
    'with-gtk-hacks=true',
    'with-main-view=true',
    'with-vapi=true',
  ],
)

libgd_vapi_dep = libgd.get_variable ('libgd_vapi_dep')
libgd_dep = libgd.get_variable('libgd_dep')

msgfmt = find_program ('msgfmt')

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
conf.set('PACKAGE_BUGREPORT', '"https://bugzilla.gnome.org/enter_bug.cgi?product=gnome-boxes"')

if govirt_dep.found()
  conf.set10 ('HAVE_OVIRT', get_option ('ovirt'))
endif

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
