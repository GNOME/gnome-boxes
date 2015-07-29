# -*- coding: UTF-8 -*-

from time import sleep, localtime, strftime
from dogtail.utils import isA11yEnabled, enableA11y
if not isA11yEnabled():
    enableA11y(True)
from dogtail.rawinput import pressKey
from subprocess import call
from common_steps import App, dummy, non_block_read, ensure_app_running
from dogtail.config import config
import os
from urllib2 import urlopen, URLError, HTTPError
import sys

def downloadfile(url):
    # Open the url
    try:
        f = urlopen(url)
        print("** Downloading: " + url)

        # Open our local file for writing
        if not os.path.isfile("%s/Downloads/%s" % (os.path.expanduser("~"), os.path.basename(url))):
            with open("%s/Downloads/%s" % (os.path.expanduser("~"), os.path.basename(url)), "wb") as local_file:
                local_file.write(f.read())

    except HTTPError, e:
        print("HTTP Error:", e.code, url)
    except URLError, e:
        print("URL Error:", e.reason, url)

def do_backup():
    f = open(os.devnull, "w")

    try:
        call("mkdir ~/boxes_backup", shell=True)

        print("** Backing up session machines")

        # First ensure all boxes are shutdown
        call("for i in $(virsh list --all|tail -n +3|head -n -1|sed -e 's/^ \(-\|[0-9]\+\) *//'|cut -d' ' -f1); do " +
             "    virsh destroy $i; done", shell=True, stdout=f, stderr=f)

        # copy configuration XML of all machines
        call("for i in $(virsh list --all|tail -n +3|head -n -1|sed -e 's/^ \(-\|[0-9]\+\) *//'|cut -d' ' -f1); do " +
             "    virsh dumpxml $i > ~/boxes_backup/$i.xml; done", shell=True, stdout=f)

        # move disk images
        call("mkdir ~/boxes_backup/images", shell=True)
        call("mv ~/.local/share/gnome-boxes/images/* ~/boxes_backup/images/ || true", shell=True, stderr=f)

        # Backup snapshots
        call("mkdir ~/boxes_backup/snapshot", shell=True)
        call("cp -R ~/.config/libvirt/qemu/snapshot/* ~/boxes_backup/snapshot/ || true", shell=True, stderr=f)

        # now remove all snapshots
        call("for i in $(virsh list --all|tail -n +3|head -n -1|sed -e 's/^ \(-\|[0-9]\+\) *//'|cut -d' ' -f1); do " +
             "    for j in $(virsh snapshot-list $i|tail -n +3|head -n -1|sed 's/^ //'|cut -d' ' -f1); do " +
             "        virsh snapshot-delete $i $j|| true; done; done", shell=True, stdout=f)

        # move save states
        call("mkdir ~/boxes_backup/save", shell=True)
        call("mv ~/.config/libvirt/qemu/save/* ~/boxes_backup/save/ || true", shell=True, stderr=f)

        # move all sources
        print("** Backing up all sources")

        call("mkdir ~/boxes_backup/sources", shell=True)
        call("mv ~/.cache/gnome-boxes/sources/* ~/boxes_backup/sources/ || true", shell=True, stderr=f)

        # create marker
        call('touch /tmp/boxes_backup', shell=True)
        print("* Done\n")

    except Exception as e:
        print("Error in backup: %s" % e.message)

    # Undefine all boxes
    call("for i in $(virsh list --all|tail -n +3|head -n -1|sed -e 's/^ \(-\|[0-9]\+\) *//'|cut -d' ' -f1); do " +
         "    virsh undefine --managed-save $i; done", shell=True, stdout=f)
    f.close()

def do_restore():
    if not os.path.isfile('/tmp/boxes_backup'):
        return

    f = open(os.devnull, "w")

    print("** Restoring Boxes backup")
    # move images back
    call("mv ~/boxes_backup/images/* ~/.local/share/gnome-boxes/images/", shell=True, stderr=f)

    # move save states back
    #call("mkdir ~/.config/libvirt/qemu/save/", shell=True, stdout=f, stderr=f)
    call("mv ~/boxes_backup/save/* ~/.config/libvirt/qemu/save/", shell=True, stdout=f, stderr=f)

    # import machines
    call("for i in $(ls ~/boxes_backup |grep xml); do virsh define ~/boxes_backup/$i; done", shell=True, stdout=f)

    # import snapshots
    # IFS moved to _ as snapshots have spaces in names
    # there are two types of snapshots running/shutoff
    # so we need to import each typo into different state running vs shutted down
    call("export IFS='_'; cd ~/boxes_backup/snapshot/; \
          for i in * ; do \
              for s in $i/*.xml; \
                  do virsh snapshot-create $i ~/boxes_backup/snapshot/$s; \
              done; \
              virsh start $i; \
              for s in $i/*.xml; \
                  do virsh snapshot-create $i ~/boxes_backup/snapshot/$s; \
              done; \
              virsh save $i ~/.config/libvirt/qemu/save/$i.save ; \
              done; cd -;", shell=True, stdout=f, stderr=f)

    call("mv ~/boxes_backup/sources/* ~/.cache/gnome-boxes/sources/", shell=True, stdout=f)

    # delete marker
    call("rm -rf /tmp/boxes_backup", shell=True, stdout=f)

    # delete backup
    call("rm -rf ~/boxes_backup", shell=True, stdout=f)

    print("* Done\n")

    f.close()

def before_all(context):
    """Setup stuff
    Being executed once before any test
    """

    try:
        if not os.path.isfile('/tmp/boxes_configured'):
            print("** Turning off gnome idle")
            if call("gsettings set org.gnome.desktop.session idle-delay 0", shell=True) == 0:
                print("PASS\n")
            else:
                print("FAIL: unable to turn off screensaver. This can cause failures")

            # Download Core-5.3.iso and images for import if not there
            downloadfile('http://distro.ibiblio.org/tinycorelinux/5.x/x86/archive/5.3/Core-5.3.iso')
            downloadfile('https://dl.dropboxusercontent.com/u/93657599/vbenes/Core-5.3.vmdk')
            downloadfile('https://dl.dropboxusercontent.com/u/93657599/vbenes/Core-5.3.qcow2')
            call('cp ~/Downloads/Core-5.3.iso /tmp', shell=True)
            call('cp ~/Downloads/Core-5.3.qcow2 /tmp', shell=True)
            call('touch /tmp/boxes_configured', shell=True)

        # Skip dogtail actions to print to stdout
        config.logDebugToStdOut = False
        config.typingDelay = 0.1
        config.childrenLimit = 500

        # Include assertion object
        context.assertion = dummy()

        # Store scenario start time for session logs
        context.log_start_time = strftime("%Y-%m-%d %H:%M:%S", localtime())

        context.app_class = App('gnome-boxes')

    except Exception as e:
        print("Error in before_all: %s" % e.message)

    do_backup()

def before_scenario(context, scenario):
    pass

def before_tag(context, tag):
    if 'vnc' in tag:
        if not os.path.isfile('/usr/bin/vncserver'):
            do_restore()
            sys.exit(77)

        os.system('vncserver -SecurityTypes None > /dev/null 2>&1')
        sleep(1)

    if 'system_broker' in tag:
        if call('pkcheck -a org.libvirt.unix.manage --process $BASHPID', shell=True) != 0 \
            or not os.path.isfile('/usr/bin/virt-install') \
            or call('systemctl status libvirtd  > /dev/null 2>&1', shell=True) != 0:
            do_restore()
            sys.exit(77)

    if 'help' in tag:
        os.system('pkill -9 yelp')

def after_step(context, step):
    try:
        if step.status == 'failed' and hasattr(context, "embed"):
            # Embed screenshot if HTML report is used
            os.system("dbus-send --print-reply --session --type=method_call " +
                      "--dest='org.gnome.Shell.Screenshot' " +
                      "'/org/gnome/Shell/Screenshot' " +
                      "org.gnome.Shell.Screenshot.Screenshot " +
                      "boolean:true boolean:false string:/tmp/screenshot.png")
            context.embed('image/png', open("/tmp/screenshot.png", 'r').read())

    except Exception as e:
        print("Error in after_step: %s" % str(e))

def after_tag(context, tag):
    if 'express_install' in tag:
        if 'express_install_fedora_20' in tag:
            call('rm -rf ~/Downloads/Fedora-20*', shell=True)
        if 'express_install_fedora_21' in tag:
            call('rm -rf ~/Downloads/Fedora-Server-netinst-x86_64-21.iso', shell=True)
        if 'express_install_fedora_22' in tag:
            call('rm -rf ~/Downloads/Fedora-Workstation-netinst-x86_64-22.iso', shell=True)

        # need to remove cache file as otherwise prefilled values may be in use
        call('rm -rf ~/.cache/gnome-boxes/unattended', shell=True)

    if 'vnc' in tag:
        os.system('vncserver -kill :1 > /dev/null 2>&1')
        os.system('rm -rf /tmp/vnc_text.txt')
        sleep(1)

    if 'help' in tag:
        os.system('pkill -9 yelp')

    if 'system_broker' in tag:
        if tag == 'pause_system_broker_box' or tag == 'resume_system_broker_box':
            os.system('virsh -q -c qemu:///system start Core-5.3 > /dev/null 2>&1')

        os.system('virsh -q -c qemu:///system destroy Core-5.3 > /dev/null 2>&1')
        os.system('virsh -q -c qemu:///system undefine Core-5.3 > /dev/null 2>&1')

        if tag == "import_2_boxs_from_system_broker":
            os.system('virsh -q -c qemu:///system destroy Core-5.3-2 > /dev/null 2>&1')
            os.system('virsh -q -c qemu:///system undefine Core-5.3-2 > /dev/null 2>&1')


def after_scenario(context, scenario):
    """Teardown for each scenario
    Kill gnome-boxes (in order to make this reliable we send sigkill)
    """

    try:
        # Remove qemu____system to avoid deleting system broker machines
        for tag in scenario.tags:
            if 'system_broker' in tag:
                call("rm -rf ~/.cache/gnome-boxes/sources/qemu____system", shell=True)
                context.app_class.quit()
                context.app_class = App('gnome-boxes')
                context.app = context.app_class.startViaCommand()

        # Attach journalctl logs
        if hasattr(context, "embed"):
            os.system("journalctl /usr/bin/gnome-session --no-pager -o cat --since='%s'> /tmp/journal-session.log" \
                                                                                            % context.log_start_time)
            data = open("/tmp/journal-session.log", 'r').read()
            if data:
                context.embed('text/plain', data)

            context.app_class.quit()

            stdout = non_block_read(context.app_class.process.stdout)
            stderr = non_block_read(context.app_class.process.stderr)

            if stdout:
                context.embed('text/plain', stdout)

            if stderr:
                context.embed('text/plain', stderr)

        f = open(os.devnull, "w")

        # Shutdown all boxes
        call("for i in $(virsh list --all|tail -n +3|head -n -1|sed -e 's/^ \(-\|[0-9]\+\) *//'|cut -d' ' -f1); do " +
             "    virsh destroy $i || true; done", shell=True, stdout=f, stderr=f)

        # Remove all snapshots
        call("for i in $(virsh list --all|tail -n +3|head -n -1|sed -e 's/^ \(-\|[0-9]\+\) *//'|cut -d' ' -f1); do " +
             "    for j in $(virsh snapshot-list $i|tail -n +3|head -n -1|sed 's/^ //'|cut -d' ' -f1); do " +
             "        virsh snapshot-delete $i $j|| true; done; done", shell=True, stdout=f, stderr=f)

        # Remove all volumes
        call("for i in $(virsh vol-list gnome-boxes|tail -n +3|head -n -1|sed 's/^ //'|cut -d' ' -f1); do " +
             "    virsh vol-delete $i gnome-boxes; done", shell=True, stdout=f)

        # Remove all save states
        call("rm -rf ~/.config/libvirt/qemu/save/*", shell=True, stderr=f)

        # Remove all sources
        call("rm -rf ~/.cache/gnome-boxes/sources/*", shell=True, stderr=f)

        # Undefine all boxes
        call("for i in $(virsh list --all|tail -n +3|head -n -1|sed -e 's/^ \(-\|[0-9]\+\) *//'|cut -d' ' -f1); do " +
             "    virsh undefine --managed-save $i; done", shell=True, stdout=f)

        f.close()

    except Exception as e:
        # Stupid behave simply crashes in case exception has occurred
        print("Error in after_scenario: %s" % e.message)

def after_all(context):
    do_restore()
