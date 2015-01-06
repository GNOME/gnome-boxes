# -*- coding: UTF-8 -*-

from behave import step
from dogtail.rawinput import pressKey
from dogtail import predicate
from time import sleep
from utils import get_showing_node_rolename, get_showing_node_name

@step(u'Focus "{window}" window')
def focus_window(context, window):
    if window == 'main':
        context.app.findChildren(lambda x: x.name == 'New' and x.showing and x.sensitive)[0].grabFocus()
    else:
        cores = context.app.findChildren(lambda x: x.name == window)
        main = context.app.children[0]
        for core in cores:
            frame = core.findAncestor(predicate.GenericPredicate(name='Boxes', roleName='frame'))
            if frame != main:
                core.grabFocus()
                sleep(0.5)
                pressKey('Tab')
                sleep(0.5)

@step(u'Open "{vm_names_list}" in new windows')
def open_new_windows(context, vm_names_list):
    vm_names = vm_names_list.split(',')
    names = []
    for name in vm_names:
        names.append(name.strip())

    if len(names) == 1:
        button = 'Open in new window'
    else:
        button = "Open in %s new windows" %len(names)

    # Click open in new windows
    context.app.findChildren(lambda x: x.name == button and x.showing and x.sensitive)[0].click()
    sleep(3)

    # Have to go to every single prefs to allow focusing, this can be done just from main window (grabFocus to main)
    boxes = context.app.findChildren(lambda x: x.name == 'Boxes')

    # For each window (aka box)
    for box in boxes:
        if box == context.app.children[0]:
            continue
        # Find New button
        context.app.findChildren(lambda x: x.name == 'New' and x.showing)[0].grabFocus()
        # Find pane which contains icons with box name as text property
        pane = context.app.children[0].child(roleName='layered pane')
        vm = names.pop()
        for icon in pane.children:
            # Icon has text property equal to box name we've found it
            if icon.text == vm:
                # Click that icon
                icon.click()
                sleep(1)
                break
        # Locate visible panel of single box
        panel = box.children[0].findChildren(lambda x: x.roleName == 'panel' and x.showing)[0]
        # Locate preference button and click it
        buttons = panel.findChildren(lambda x: x.roleName == 'push button' \
                                               and not x.name and x.showing and x.sensitive)
        buttons[0].click()

        timer = 0
        # Wait up to 5 seconds for panel with Back button to appear
        while True:
            sleep(1)
            box_panel = get_showing_node_rolename('panel', box.children[0])
            if box_panel != panel:
                break
            timer += 1
            if timer == 5:
                raise Exception("Timeout: Back button's panel wasn't found showing")

        # Locate visible panel again
        panel = box.children[0].findChildren(lambda x: x.roleName == 'panel' and x.showing)[0]
        # Wait for back button to be shown

        get_showing_node_name('Back', panel).click()
        sleep(1)
