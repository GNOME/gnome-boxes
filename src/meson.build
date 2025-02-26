common_sources = [
  'async-launcher.vala',
  'box-config.vala',
  'collection-source.vala',
  'util.vala',
]

vala_args = [
  '--enable-experimental',
  '--vapidir', vapi_dir,
  '--vapidir', join_paths (vapi_dir, 'upstream'),
  '--target-glib=2.38',
]

common_dependencies = [
  config_h,
  config_dep,
  libarchive_dep,
  dependency ('gio-2.0', version: '>= 2.44.0'),
  dependency ('glib-2.0', version: '>= 2.44.0')
]

c_args = [
  '-DDATADIR="' + data_dir + '"',
  '-DGNOMELOCALEDIR="' + locale_dir + '"',
  '-DGETTEXT_PACKAGE="gnome-boxes"',
  '-DCACHEDIR="/var/cache/"',
  '-DG_LOG_DOMAIN="Boxes"',
  '-w',
]

if get_option ('buildtype').contains ('debug')
  c_args += ['-O0', '-ggdb3']
endif

libcommon = static_library(
  'common',
  sources: common_sources,
  include_directories: config_h_dir,
  dependencies: common_dependencies,
  vala_args: vala_args,
  c_args: c_args
)

vala_sources = [
  'app.vala',
  'app-window.vala',
  'actions-popover.vala',
  'archive-reader.vala',
  'archive-writer.vala',
  'collection.vala',
  'collection-toolbar.vala',
  'display-page.vala',
  'display-toolbar.vala',
  'display.vala',
  'downloads-hub.vala',
  'icon-view.vala',
  'installer-media.vala',
  'installed-media.vala',
  'keys-input-popover.vala',
  'libvirt-cloned-media.vala',
  'libvirt-media.vala',
  'iso-extractor.vala',
  'icon-view-child.vala',
  'libvirt-broker.vala',
  'libvirt-machine.vala',
  'list-view.vala',
  'list-view-row.vala',
  'machine.vala',
  'main.vala',
  'media-manager.vala',
  'os-database.vala',
  'searchbar.vala',
  'shared-folders.vala',
  'spice-display.vala',
  'transfer-info-row.vala',
  'transfer-popover.vala',
  'troubleshoot-view.vala',
  'topbar.vala',
  'ui.vala',
  'unattended-installer.vala',
  'unattended-file.vala',
  'util-app.vala',
  'vm-configurator.vala',
  'vm-creator.vala',
  'vm-importer.vala',
  'libvirt-vm-cloner.vala',
  'libvirt-vm-importer.vala',
  'welcome-tutorial.vala',
  'welcome-tutorial-page.vala',
  'downloader.vala',
]

subdir('ui')
subdir('assistant')
subdir('preferences')

dependencies = [
  config_h,
  config_dep,
  libarchive_dep,
  dependency ('gobject-2.0', version: '>= 2.44'),
  dependency ('gtk+-3.0', version: '>= 3.22.20'),
  dependency ('libportal', version: '>= 0.7'),
  dependency ('libportal-gtk3', version: '>= 0.7'),
  dependency ('libhandy-1', version: '>= 1.5.0'),
  dependency ('libosinfo-1.0', version: '>= 1.10.0'),
  dependency ('libsoup-3.0'),
  dependency ('libusb-1.0', version: '>= 1.0.9'),
  dependency ('libvirt-gconfig-1.0', version: '>= 5.0.0'),
  dependency ('libvirt-gobject-1.0', version: '>= 5.0.0'),
  dependency ('libxml-2.0', version: '>= 2.7.8'),
  dependency ('spice-client-gtk-3.0', version: '>= 0.32'),
  dependency ('webkit2gtk-4.1'),
  cc.find_library('m', required : false),
  valac.find_library ('gio-2.0-workaround', dirs: vapi_dir),
  valac.find_library ('linux'),
  valac.find_library ('posix'),
  valac.find_library ('spice-client-gtk-3.0'),
]

if get_option('flatpak')
  vala_args += '--define=FLATPAK'

  dependencies += dependency ('govf-0.1')
else
  dependencies += [
    dependency ('gudev-1.0', version: '>= 165'),
  ]

  libovf = subproject(
    'libovf-glib',
    default_options: [
      'package_subdir=' + meson.project_name()
    ]
  )

  dependencies += libovf.get_variable('govf_vapi')
endif

executable ('gnome-boxes', vala_sources + resources,
            include_directories: config_h_dir,
            vala_args: vala_args,
            c_args : c_args,
            dependencies: dependencies,
            link_with: libcommon,
            install: true,
            install_rpath: join_paths (get_option ('prefix'), get_option ('libdir'), 'gnome-boxes')
)

executable ('gnome-boxes-search-provider', 'gnome-boxes-search-provider.vala',
            include_directories: config_h_dir,
            vala_args: vala_args,
            c_args: c_args,
            dependencies: common_dependencies,
            link_with: libcommon,
            install: true,
            install_dir: get_option ('libexecdir')
)
