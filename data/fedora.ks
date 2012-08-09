install
keyboard BOXES_FEDORA_KBD
lang BOXES_LANG
network --onboot yes --device eth0 --bootproto dhcp --noipv6 --hostname=BOXES_HOSTNAME --activate
rootpw BOXES_PASSWORD
firewall --disabled
authconfig --enableshadow --enablemd5
selinux --enforcing
timezone --utc BOXES_TZ
bootloader --location=mbr
zerombr
clearpart --all --drives=vda

firstboot --disable

part biosboot --fstype=biosboot --size=1
part /boot --fstype ext4 --recommended --ondisk=vda
part pv.2 --size=1 --grow --ondisk=vda
volgroup VolGroup00 --pesize=32768 pv.2
logvol swap --fstype swap --name=LogVol01 --vgname=VolGroup00 --size=768 --grow --maxsize=1536
logvol / --fstype ext4 --name=LogVol00 --vgname=VolGroup00 --size=1024 --grow
reboot

user --name=BOXES_USERNAME --password=BOXES_PASSWORD

%packages
@base
@core
@hardware-support
@base-x
@gnome-desktop
@graphical-internet
@sound-and-video

BOXES_FEDORA_SPICE_PACKAGES

%end

%post --erroronfail

# Add user to admin group
usermod -a -G wheel BOXES_USERNAME

# Set user avatar
mkdir /mnt/unattended-media
mount /dev/sda /mnt/unattended-media
cp /mnt/unattended-media/BOXES_USERNAME /var/lib/AccountsService/icons/
umount /mnt/unattended-media
echo "
[User]
Language=
XSession=
Icon=/var/lib/AccountsService/icons/BOXES_USERNAME
" >> /var/lib/AccountsService/users/BOXES_USERNAME

# Enable autologin
echo "[daemon]
AutomaticLoginEnable=true
AutomaticLogin=BOXES_USERNAME

[security]

[xdmcp]

[greeter]

[chooser]

[debug]
" > /etc/gdm/custom.conf

%end
