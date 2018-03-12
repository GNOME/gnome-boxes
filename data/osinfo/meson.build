osinfo_db = [
  ['debian-4.xml', 'gnome-boxes/osinfo/os/debian.org'],
  ['eos-3.3.xml', 'gnome-boxes/osinfo/os/endlessos.com'],
  ['fedora-1.xml', 'gnome-boxes/osinfo/os/fedoraproject.org'],
  ['freedos-1.2.xml', 'gnome-boxes/osinfo/os/freedos.org'],
  ['opensuse-10.2.xml', 'gnome-boxes/osinfo/os/opensuse.org'],
  ['ubuntu-4.10.xml', 'gnome-boxes/osinfo/os/ubuntu.com'],
  ['gnome-3.6.xml', 'gnome-boxes/osinfo/os/gnome.org'],
  ['rhel-4.0.xml', 'gnome-boxes/osinfo/os/redhat.com'],
  ['rhel-5.0.xml', 'gnome-boxes/osinfo/os/redhat.com'],
  ['rhel-6.0.xml', 'gnome-boxes/osinfo/os/redhat.com'],
  ['rhel-7.0.xml', 'gnome-boxes/osinfo/os/redhat.com']
]

foreach os: osinfo_db
  install_data (os[0], install_dir : join_paths (data_dir, os[1]))
endforeach
