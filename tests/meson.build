tests_names = [
  'express-install.feature',
  'general.feature',
  'import-vms.feature',
  'livecd.feature',
  'multi-windows.feature',
  'snapshots.feature',
  'spice.feature',
  'system-broker.feature'
]

tests_execdir = join_paths (get_option('prefix'), get_option ('libexecdir'), meson.project_name (), 'installed-tests')
tests_metadir = join_paths (get_option ('datadir'), 'installed-tests', meson.project_name ())

foreach test_name: tests_names
  tests_conf = configuration_data ()
  tests_conf.set ('TESTS_PATH', tests_execdir)
  tests_conf.set ('TEST_NAME', test_name)
  tests_conf.set ('TEST_TYPE', 'session-exclusive')

  configure_file (
    input: 'template.test.in',
    output: test_name + '.test',
    install: true,
    install_dir: tests_metadir,
    configuration: tests_conf
  )
endforeach

tests_files = tests_names + [
  'common_steps.py',
  'environment.py'
]

install_data (tests_files, install_dir: tests_execdir)

install_subdir ('steps', install_dir: tests_execdir)
