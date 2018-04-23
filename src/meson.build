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
]

common_dependencies = [
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
  'auth-notification.vala',
  'collection.vala',
  'collection-filter-switcher.vala',
  'collection-toolbar.vala',
  'display-page.vala',
  'display-toolbar.vala',
  'display.vala',
  'editable-entry.vala',
  'i-properties-provider.vala',
  'i-collection-view.vala',
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
  'libvirt-machine-properties.vala',
  'list-view.vala',
  'list-view-row.vala',
  'machine.vala',
  'machine-thumbnailer.vala',
  'main.vala',
  'media-manager.vala',
  'resource-graph.vala',
  'notification.vala',
  'notificationbar.vala',
  'os-database.vala',
  'properties.vala',
  'properties-window.vala',
  'properties-page-widget.vala',
  'properties-toolbar.vala',
  'remote-machine.vala',
  'search.vala',
  'searchbar.vala',
  'selectionbar.vala',
  'selection-toolbar.vala',
  'shared-folder-popover.vala',
  'spice-display.vala',
  'transfer-info-row.vala',
  'transfer-popover.vala',
  'troubleshoot-view.vala',
  'topbar.vala',
  'ui.vala',
  'unattended-installer.vala',
  'unattended-file.vala',
  'unattended-setup-box.vala',
  'util-app.vala',
  'vm-configurator.vala',
  'vm-creator.vala',
  'vm-importer.vala',
  'libvirt-system-importer.vala',
  'libvirt-vm-cloner.vala',
  'libvirt-vm-importer.vala',
  'vnc-display.vala',
  'wizard-downloads-page.vala',
  'wizard-window.vala',
  'wizard-source.vala',
  'wizard-toolbar.vala',
  'wizard.vala',
  'downloader.vala',
  'empty-boxes.vala',
  'tracker-iso-query.vala',
  'troubleshoot-log.vala',
  'snapshot-list-row.vala',
  'snapshots-property.vala',
]

dependencies = [
  config_dep,
  libarchive_dep,
  dependency ('gobject-2.0', version: '>= 2.44'),
  dependency ('gtk+-3.0', version: '>= 3.22.20'),
  dependency ('gtk-vnc-2.0', version: '>= 0.4.4'),
  dependency ('gudev-1.0', version: '>= 165'),
  dependency ('libosinfo-1.0', version: '>= 1.1.0'),
  dependency ('libsecret-1'),
  dependency ('libsoup-2.4', version: '>= 2.38'),
  dependency ('libusb-1.0', version: '>= 1.0.9'),
  dependency ('libvirt-gconfig-1.0', version: '>= 0.2.0'),
  dependency ('libvirt-gobject-1.0', version: '>= 0.2.0'),
  dependency ('libxml-2.0', version: '>= 2.7.8'),
  dependency ('spice-client-gtk-3.0', version: '>= 0.32'),
  dependency ('tracker-sparql-2.0'),
  dependency ('webkit2gtk-4.0'),
  valac.find_library ('gio-2.0-workaround', dirs: vapi_dir),
  valac.find_library ('linux'),
  valac.find_library ('posix'),
  valac.find_library ('spice-client-gtk-3.0'),
]

if get_option('ovirt')
  vala_sources += [
    'ovirt-broker.vala',
    'ovirt-machine.vala'
  ]

  vala_args += '--define=HAVE_OVIRT'

  dependencies += [
    dependency ('govirt-1.0', version: '>= 0.3.4'),
    valac.find_library ('rest-0.7')
  ]
endif

# Gtk-fRDP
pkgdatadir = join_paths (data_dir, meson.project_name ())
gtk_frdp = subproject(
  'gtk-frdp',
  default_options: [
    'pkgdatadir=' + pkgdatadir,
    'pkglibdir=' + pkglibdir
  ]
)

dependencies += gtk_frdp.get_variable('gtk_frdp_vapi')

executable ('gnome-boxes', vala_sources + resources,
            include_directories: config_h_dir,
            vala_args: vala_args,
            c_args : c_args,
            dependencies: dependencies,
            link_with: libcommon,
            install: true
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
