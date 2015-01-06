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
        print "** Downloading: " + url

        # Open our local file for writing
        if not os.path.isfile("%s/Downloads/%s" % (os.path.expanduser("~"), os.path.basename(url))):
            with open("%s/Downloads/%s" % (os.path.expanduser("~"), os.path.basename(url)), "wb") as local_file:
                local_file.write(f.read())

    except HTTPError, e:
        print "HTTP Error:", e.code, url
    except URLError, e:
        print "URL Error:", e.reason, url

def before_all(context):
    """Setup stuff
    Being executed once before any test
    """

    try:
        if not os.path.isfile('/tmp/boxes_configured'):
            print "** Turning off gnome idle"
            if call("gsettings set org.gnome.desktop.session idle-delay 0", shell=True) == 0:
                print "PASS\n"
            else:
                print "FAIL: unable to turn off screensaver. This can cause failures"

            # Download Core-5.3.iso and images for import if not there
            downloadfile('http://distro.ibiblio.org/tinycorelinux/5.x/x86/archive/5.3/Core-5.3.iso')
            downloadfile('https://dl.dropboxusercontent.com/u/93657599/vbenes/Core-5.3.vmdk')
            downloadfile('https://dl.dropboxusercontent.com/u/93657599/vbenes/Core-5.3.qcow2')
            call('cp ~/Downloads/Core-5.3.iso /tmp', shell=True)
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
        print "Error in before_all: %s" % e.message

def before_scenario(context, scenario):
    pass

def before_tag(context, tag):
    if 'system_broker' in tag:
        if call('pkcheck -a org.libvirt.unix.manage --process $BASHPID', shell=True) != 0 \
            or not os.path.isfile('/usr/bin/virt-install') \
            or call('systemctl status libvirtd  > /dev/null 2>&1', shell=True) != 0:

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
        print "Error in after_step: %s" % str(e)

def after_tag(context, tag):
    if 'help' in tag:
        os.system('pkill -9 yelp')

    if 'system_broker' in tag:
        if tag == 'pause_system_broker_box' or tag == 'resume_system_broker_box':
            os.system('virsh -q -c qemu:///system start Core-5.3 > /dev/null 2>&1')

        os.system('virsh -q -c qemu:///system destroy Core-5.3 > /dev/null 2>&1')
        os.system('virsh -q -c qemu:///system undefine Core-5.3 > /dev/null 2>&1')

def after_scenario(context, scenario):
    """Teardown for each scenario
    Kill gnome-boxes (in order to make this reliable we send sigkill)
    """

    try:

    # Delete all boxes from GUI
        if context.app_class.isRunning():
            new = context.app.findChildren(lambda x: x.name == 'New')[0]

            # Is new visible?
            if not new.showing:
            # ave to press back button if visible
                backs = context.app.findChildren(lambda x: x.name == 'Back' and x.showing)
                if backs:
                    backs[0].click()

            # Is new finally visible?
            new = context.app.findChildren(lambda x: x.name == 'New')[0]
            if not new.showing:
            # Have to press vm unnamed back button
                panel = context.app.child('Boxes').children[0].findChildren(lambda x: x.roleName == 'panel' \
                                                                                                     and x.showing)[0]
                buttons = panel.findChildren(lambda x: x.roleName == 'push button' and x.showing)
                if buttons:
                    buttons[0].click()

            new.grabFocus()
            pane = context.app.child(roleName='layered pane')
            if len(pane.children) != 0:
                for child in pane.children:
                    child.click(button=3)
                context.app.findChildren(lambda x: x.name == 'Delete' and x.showing)[0].click()
                context.app.findChildren(lambda x: x.name == 'Undo' and x.showing)[0].grabFocus()
                pressKey('Tab')
                pressKey('Enter')
                sleep(2)

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

    except Exception as e:
        # Stupid behave simply crashes in case exception has occurred
        print "Error in after_scenario: %s" % e.message

    # clean all boxes
    os.system("rm -rf ~/.config/libvirt/storage/*")
    os.system("rm -rf ~/.cache/gnome-boxes/sources/qemu*")
    os.system("rm -rf ~/.local/share/gnome-boxes/images/*")
