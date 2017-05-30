project ('gnome-boxes',
         ['vala', 'c'],
         version: '3.25.3',
         license: 'LGPLv2+',
         meson_version: '>= 0.40',
)

gnome = import ('gnome')
i18n = import ('i18n')

glib = dependency ('glib-2.0', version: '>= 2.38.0')
gio = dependency ('gio-2.0', version: '>= 2.38.0')
gobject = dependency ('gobject-2.0', version: '>= 2.44')
govirt = dependency ('govirt-1.0', version: '>= 0.3.4')
gtk = dependency ('gtk+-3.0', version: '>= 3.19.8')
gtk_vnc = dependency ('gtk-vnc-2.0', version: '>= 0.4.4')
gudev = dependency ('gudev-1.0', version: '>= 165')
libarchive = dependency ('libarchive', version: '>= 3.0.0')
libosinfo = dependency ('libosinfo-1.0', version: '>= 0.2.12')
libsecret = dependency ('libsecret-1')
libsoup = dependency ('libsoup-2.4', version: '>= 2.38')
libusb = dependency ('libusb-1.0', version: '>= 1.0.9')
libvirt_glib = dependency ('libvirt-gobject-1.0', version: '>= 0.2.0')
libvirt_gconfig = dependency ('libvirt-gconfig-1.0', version: '>= 0.2.0')
libxml = dependency ('libxml-2.0', version: '>= 2.7.8')
spice_client_gtk = dependency ('spice-client-gtk-3.0', version: '>= 0.32')
tracker = dependency ('tracker-sparql-1.0')

cc = meson.get_compiler ('c')

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
locale_dir = join_paths (data_dir, '/locale')

conf = configuration_data ()
conf.set_quoted ('PACKAGE_NAME', meson.project_name ())
conf.set_quoted ('PACKAGE_TARNAME', meson.project_name ())
conf.set_quoted ('PACKAGE_VERSION', meson.project_version ())
conf.set_quoted ('GETTEXT_PACKAGE', meson.project_name ())
conf.set('PACKAGE_URL', '"https://wiki.gnome.org/Apps/Boxes"')
conf.set_quoted ('VERSION', meson.project_version ())
conf.set_quoted ('DATADIR', data_dir)
conf.set_quoted ('CACHEDIR', '/var/cache')
conf.set_quoted ('LOCALEDIR', locale_dir)
conf.set('PACKAGE_BUGREPORT', '"https://bugzilla.gnome.org/enter_bug.cgi?product=gnome-boxes"')

if govirt.found()
  conf.set10 ('HAVE_OVIRT', get_option ('enable-ovirt'))
endif

configure_file (output: 'config.h', configuration: conf)
config_h_dir = include_directories ('.')

meson.add_install_script (join_paths ('build-aux', 'post_install.py'))

subdir ('data')
subdir ('help')
subdir ('po')
subdir ('src')
