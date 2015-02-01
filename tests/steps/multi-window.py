# -*- coding: UTF-8 -*-

from __future__ import unicode_literals
from behave import step
from dogtail.rawinput import pressKey
from dogtail import predicate
from time import sleep
from utils import get_showing_node_rolename, get_showing_node_name

def find_window(context, name):
    target = None
    for window in context.app.children:
        if window.name == name:
            target = window

            break

    if target == None:
        raise Exception("Window for %s was not found" %vm_name)

    return target

@step('Focus "{window}" window')
def focus_window(context, window):
    if window == 'main':
        context.app.findChildren(lambda x: x.name == 'New' and x.showing and x.sensitive)[0].grabFocus()
    else:
        core = find_window(context, window)
        button = core.findChildren(lambda x: x.roleName == 'toggle button' and x.showing)[1]
        button.grabFocus()
        sleep(0.5)
        pressKey('Tab')
        sleep(0.5)

@step('Open "{vm_names_list}" in new windows')
def open_new_windows(context, vm_names_list):
    vm_names = vm_names_list.split(', ')

    if len(vm_names) == 1:
        button = 'Open in new window'
    else:
        button = "Open in %s new windows" %len(vm_names)

    # Click open in new windows
    context.app.findChildren(lambda x: x.name == button and x.showing and x.sensitive)[0].click()
    sleep(3)

    for vm_name in vm_names:
        # Ensure we have a window for each box
        find_window(context, vm_name)
