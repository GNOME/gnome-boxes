# -*- coding: UTF-8 -*-

from __future__ import unicode_literals
from behave import step
from dogtail.tree import root
from dogtail.rawinput import typeText, pressKey, keyCombo
from time import sleep
from common_steps import wait_until
from subprocess import call, check_output, Popen, CalledProcessError, PIPE
import re
import libvirt
import libxml2

@step('About is shown')
def about_shown(context):
    assert context.app.child('About Boxes') != None, "About window cannot be focused"

@step('Box "{name}" "{state}" exist')
def does_box_exists(context, name, state):
    found = False
    pane = context.app.child(roleName='layered pane')
    for child in pane.children:
        if child.text == name:
            found = True
            break

    if state == 'does':
        assert found == True, "Machine %s was not found in overview" % name
    if state == 'does not':
        assert found == False, "Machine %s was found in overview" % name

@step('Boxes are not running')
def boxes_not_running(context):
    assert context.app_class.isRunning() != True, "Boxes window still visible"

@step('Boxes app has "{num}" windows')
def number_of_windows(context, num):
    assert len(context.app.children) == int(num), "App has just %s windows not %s" %(len(context.app.children), num)

@step('Customize mem to "{mem}" MB')
def customize_vm(context, mem):
    context.app.child('Customize…').click()
    sleep(0.5)
    pressKey('Tab')
    pressKey('Tab')
    memory_label = context.app.findChildren(lambda x: x.name == 'Memory: ' and x.showing)[0]
    mem = mem+" MiB"
    counter = 0
    while not memory_label.parent.findChildren(lambda x: x.name == mem and x.showing):
        pressKey('Left')
        counter += 1
        if counter == 100:
            break
    context.app.findChildren(lambda x: x.name == 'Back' and x.showing)[0].click()
    sleep(0.5)

@step('Focus VM')
def focus_vm(context):
    drawing_area = None
    drawing_area = context.app.findChildren(lambda x: x.roleName == 'drawing area' and x.showing)
    if drawing_area:
        drawing_area[0].click()

@step('Go into "{vm}" box')
def go_into_vm(context, vm):
    pane = context.app.child(roleName='layered pane')
    for child in pane.children:
        if child.text == vm:
            child.click()
            sleep(0.5)
            break

@step('Help is shown')
def help_shown(context):
    sleep(1)
    yelp = root.application('yelp')
    assert yelp.child('Boxes') != None, "Yelp wasn't opened"

@step('Install TC Linux package "{pkg}" and wait "{time}" seconds')
def install_tc_linux_package(context, pkg, time):
    if "/" in pkg:
        call("xdotool type --delay 150 'wget %s\n'" %pkg, shell=True)
        call("xdotool type --delay 150 'tce-load -i %s\n'" %pkg.split('/')[-1], shell=True)
    else:
        typeText('tce-load -wi %s\n' %pkg)

    sleep(int(time))

@step('No box is visible')
def no_box_sign(context):
    assert context.app.child('Just hit the New button to create your first one.') != None

@step('Press "{action}" in "{vm}" vm')
def press_back_in_vm(context, action, vm):
    panel = context.app.child(vm).children[0].findChildren(lambda x: x.roleName == 'panel' and x.showing)[0]
    buttons = panel.findChildren(lambda x: x.roleName == 'push button' and x.showing)
    menus = panel.findChildren(lambda x: x.name == 'Menu' and x.showing)
    if action == 'back':
        buttons[0].click()
    elif action == 'prefs':
        buttons[1].click()
    elif action == "Send key combinations":
        menus[0].click()
    else:
        context.app.child(vm).child(action).click()
    sleep(0.5)

@step('Launch "{action}" for "{box}" box')
def launch_action_for_box(context, action, box):
    pane = context.app.child(roleName='layered pane')
    item = pane.findChildren(lambda x: x.text == box and x.roleName == 'icon')[0]
    item.click(button=3)
    popup = context.app.findChildren(lambda x: x.name == 'Box actions' and x.roleName == 'popup menu' and x.showing)[0]
    popup.child(action).click()
    sleep(0.5)

@step('Press "{action}" in alert')
def press_back_in_prefs(context, action):
    button = context.app.child(roleName='alert').child(action)
    button.click()
    sleep(0.5)

@step('Quit Boxes')
def quit_boxes(context):
    keyCombo('<Ctrl><Q>')
    counter = 0
    while call('pidof gnome-boxes > /dev/null', shell=True) != 1:
        sleep(0.5)
        counter += 1
        if counter == 100:
            raise Exception("Failed to turn off Boxes in 50 seconds")


@step('Rename "{machine}" to "{name}" via "{way}"')
def rename_vm(context, machine, name, way):
    if way == 'button':
        context.app.child(machine, roleName='push button').click()
        sleep(0.5)
    if way == 'label':
        context.app.child('General').child('Name').parent.child(roleName='text').click()
        keyCombo('<Ctrl><a>')
    typeText(name)
    pressKey('Enter')
    sleep(0.5)

def libvirt_domain_get_context(dom):
    xmldesc = dom.XMLDesc(0)
    doc = libxml2.parseDoc(xmldesc)
    return doc.xpathNewContext()

def libvirt_domain_get_val(ctx, path):
    res = ctx.xpathEval(path)
    if res is None or len(res) == 0:
        value="Unknown"
    else:
        value = res[0].content
    return value

def libvirt_domain_get_mac(vm_title):
    mac = None

    conn = libvirt.openReadOnly(None)
    doms = conn.listAllDomains()
    for dom in doms:
        try:
            dom0 = conn.lookupByName(dom.name())
            # Annoyiingly, libvirt prints its own error message here
        except libvirt.libvirtError:
            print("Domain %s is not running" % name)
        ctx = libvirt_domain_get_context(dom0)
        if libvirt_domain_get_val(ctx, "/domain/title") == vm_title:
            return libvirt_domain_get_val(ctx, "/domain/devices/interface/mac/@address")

    conn = libvirt.openReadOnly('qemu:///system')
    doms = conn.listAllDomains()
    for dom in doms:
        try:
            dom0 = conn.lookupByName(dom.name())
            # Annoyiingly, libvirt prints its own error message here
        except libvirt.libvirtError:
            print("Domain %s is not running" % name)
        ctx = libvirt_domain_get_context(dom0)
        if libvirt_domain_get_val(ctx, "/domain/name") == vm_title:
            return libvirt_domain_get_val(ctx, "/domain/devices/interface/mac/@address")
    return mac

def get_ip_from_ip_neigh_cmd(mac):
    out = ""
    wait = 0
    while wait < 120:
        cmd = Popen("ip neigh show nud reachable\
                        |grep %s\
                        |tail -n 1\
                        |grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'"
                        %mac, shell=True, stdout=PIPE)

        out = cmd.communicate()[0]
        ret = cmd.wait()
        if out != "":
            return out.strip()
        sleep(0.25)
        wait += 1
    return None

@step('Save IP for machine "{vm}"')
def save_ip_for_vm(context, vm):
    if not hasattr(context, 'ips'):
        context.ips = {}

    ip = get_ip_from_ip_neigh_cmd(libvirt_domain_get_mac(vm))

    if not ip:
        raise Exception("No address was assigned for this machine %s" %vm)

    count = 1
    for key in context.ips.keys():
        if key.find(vm) != -1:
            count += 1
    if count != 1:
        vm = vm + " %s" %count

    context.ips[vm] = ip

@step('Select "{vm}" box')
def select_vm(context, vm):
    select_button = context.app.child('Select Items')
    if select_button.showing:
        select_button.click()
    pane = context.app.child(roleName='layered pane')
    for child in pane.children:
        if child.text == vm:
            child.click()
            sleep(0.2)
            break

@step('Select "{action}" from supermenu')
def select_menu_action(context, action):
    keyCombo("<Super_L><F10>")
    if action == 'About':
        pressKey('Down')
    if action == 'Quit':
        pressKey('Down')
        pressKey('Down')
    pressKey('Enter')

@step('Start Boxes')
def start_boxes(context):
    cmd = 'gnome-boxes'
    Popen(cmd, shell=True)
    sleep(1)
    context.app = root.application('gnome-boxes')

@step('Start showkey signal recording')
def start_showkey_recording(context):
    # Have to sleep a bit before as otherwise release of return can be caught
    call("xdotool type --delay 100 'sleep 0.5; showkey > /tmp/showkey.txt\n'", shell=True)
    sleep(1)

@step('Verify previously recorded signals')
def verify_existing_showkey_signals(context):
    call("xdotool type --delay 100 'grep keycode /tmp/showkey.txt > /tmp/final.txt\n'", shell=True)
    # If all signals received as expected
    call("xdotool type --delay 100 'if [[ \"$(echo $(sed \"s/keycode//g\" /tmp/final.txt))\" == '", shell=True)
    call("xdotool type --delay 100 ' \"29 press 56 press 14 press 14 release 56 release 29 release'", shell=True)
    call("xdotool type --delay 100 ' 29 press 56 press 59 press 59 release 56 release 29 release'", shell=True)
    call("xdotool type --delay 100 ' 29 press 56 press 60 press 60 release 56 release 29 release'", shell=True)
    call("xdotool type --delay 100 ' 29 press 56 press 65 press 65 release 56 release 29 release\"'", shell=True)
    # Turn down network so observer from outside the VM can say pass/fail.
    call("xdotool type --delay 100 ' ]]; then sudo ifconfig eth0 down; fi\n'", shell=True)
    sleep(0.5)

@step('Start box name "{box}"')
def start_boxes_via_vm(context, box):
    cmd = 'gnome-boxes %s' %box
    Popen(cmd, shell=True)
    sleep(5)
    context.app = root.application('gnome-boxes')

@step('Verify back button "{state}" visible for machine "{vm_name}"')
def verify_back_button_visibility(context, state, vm_name):
    if state == "is":
        main = context.app.children[0]
        core = context.app.findChildren(lambda x: x.name == vm_name)[-1]
        frame = core.findAncestor(predicate.GenericPredicate(name='Boxes', roleName='frame'))
        assert frame != main, "Cannot focus detached window"
        top_frame_panel = frame.children[0]
        main_window_panel = top_frame_panel.children[-1]
        back_button = main_window_panel.child(roleName='push button')
        assert back_button.showing == False, "Back button is visible but it shouldn't be"

@step('Wait until overview is loaded')
def initial_page_loaded(context):
    wait_until(lambda x: x.name != 'New', context.app)
