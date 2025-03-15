osinfo_db = [
  ['archlinux-rolling.xml', 'gnome-boxes/osinfo/os/archlinux.org'],
  ['centos-7.0.xml', 'gnome-boxes/osinfo/os/centos.org'],
  ['centos-stream-9.xml', 'gnome-boxes/osinfo/os/centos.org'],
  ['debian-4.xml', 'gnome-boxes/osinfo/os/debian.org'],
  ['eos-3.3.xml', 'gnome-boxes/osinfo/os/endlessos.com'],
  ['fedora-1.xml', 'gnome-boxes/osinfo/os/fedoraproject.org'],
  ['freedos-1.2.xml', 'gnome-boxes/osinfo/os/freedos.org'],
  ['gnome-nightly.xml', 'gnome-boxes/osinfo/os/gnome.org'],
  ['gnome-3.38.xml', 'gnome-boxes/osinfo/os/gnome.org'],
  ['guix-system-1.1.xml', 'gnome-boxes/osinfo/os/guix.gnu.org'],
  ['manjaro-rolling.xml', 'gnome-boxes/osinfo/os/manjaro.org'],
  ['nixos-20.03.xml', 'gnome-boxes/osinfo/os/nixos.org'],
  ['opensuse-10.2.xml', 'gnome-boxes/osinfo/os/opensuse.org'],
  ['ubuntu-4.10.xml', 'gnome-boxes/osinfo/os/ubuntu.com'],
  ['popos-17.10.xml', 'gnome-boxes/osinfo/os/system76.com'],
  ['rhel-8.0.xml', 'gnome-boxes/osinfo/os/redhat.com'],
  ['rocky-8.4.xml', 'gnome-boxes/osinfo/os/rockylinux.org'],
  ['silverblue-28.xml', 'gnome-boxes/osinfo/os/fedoraproject.org'],
  ['trisquel-9.xml', 'gnome-boxes/osinfo/os/trisquel.info']
]

foreach os: osinfo_db
  install_data (os[0], install_dir : join_paths (data_dir, os[1]))
endforeach
