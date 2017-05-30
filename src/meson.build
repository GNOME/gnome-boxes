common_sources = [
  'async-launcher.vala',
  'box-config.vala',
  'collection-source.vala',
  'util.vala',
]

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
  'searchbar.vala',
  'selectionbar.vala',
  'selection-toolbar.vala',
  'shared-folder-popover.vala',
  'spice-display.vala',
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

if govirt.found ()
  if get_option ('enable-ovirt')
    vala_sources += [
      'ovirt-broker.vala',
      'ovirt-machine.vala',
    ]
  endif
endif

boxes_sources = [
  common_sources,
  vala_sources,
  resources
]

vala_args = [
  '--enable-experimental',
  '--target-glib', '2.44',
  '--vapidir', meson.current_source_dir (),
  '--vapidir', join_paths (meson.source_root (), 'vapi'),
  '--vapidir', join_paths (meson.source_root (), 'vapi', 'upstream'),
  '--vapidir', join_paths (meson.build_root (), 'subprojects', 'libgd', 'libgd'),
  '--pkg', 'config',
  '--pkg', 'gio-2.0-workaround',
  '--pkg', 'posix',
  '--pkg', 'linux',
  '--pkg', 'rest-0.7',
  '--gresources', resource_files,
]

if get_option ('enable-debug')
  vala_args += '-g'
endif

dependencies = [
  glib,
  gio,
  gobject,
  gtk,
  gtk_vnc,
  libgd_vapi_dep,
  libgd_dep,
  libsecret,
  libvirt_glib,
  libvirt_gconfig,
  libxml,
  libusb,
  spice_client_gtk,
  gudev,
  libosinfo,
  libsoup,
  libarchive,
  tracker,
]

if govirt.found()
  if get_option ('enable-ovirt')
    dependencies += govirt
  endif
endif

c_args = [
  '-DDATADIR="' + data_dir + '"',
  '-DGNOMELOCALEDIR="' + locale_dir + '"',
  '-DGETTEXT_PACKAGE="gnome-boxes"',
  '-DCACHEDIR="/var/cache/"',
  '-DG_LOG_DOMAIN="Boxes"',
]

if get_option ('enable-debug')
  c_args += ['-00 -ggdb3']
endif

if get_option ('enable-strict-cc')
  c_args += ['-Wall', '-Werror']
endif

executable ('gnome-boxes', boxes_sources,
            include_directories: config_h_dir,
            vala_args: vala_args,
            c_args : c_args,
            dependencies: dependencies,
            install: true
)
