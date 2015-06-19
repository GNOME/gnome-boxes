# -*- coding: UTF-8 -*-

from __future__ import unicode_literals
from behave import step
from dogtail.rawinput import typeText, pressKey
from time import sleep
from utils import get_showing_node_name

@step('Add Snapshot named "{name}"')
def add_snapshot(context, name):
    wait = 0
    while len(context.app.findChildren(lambda x: x.roleName == 'push button' and x.showing and not x.name)) == 0:
        sleep(0.25)
        wait += 1
        if wait == 20:
            raise Exception("Timeout: Node %s wasn't found showing" %name)

    context.app.findChildren(lambda x: x.roleName == 'push button' and x.showing and not x.name)[0].click()

    wait = 0
    while len(context.app.findChildren(lambda x: x.roleName == 'toggle button' and x.showing \
                                                                            and x.sensitive and x.name == 'Menu')) == 0:
        sleep(0.25)
        wait += 1
        if wait == 80:
            raise Exception("Timeout: Node %s wasn't found showing" %name)

    sleep(1)
    context.app.findChildren(lambda x: x.roleName == 'toggle button' and x.showing \
                                                                     and x.sensitive and x.name == 'Menu')[-1].click()

    renames = context.app.findChildren(lambda x: x.name == 'Rename' and x.showing)
    if not renames:
        context.app.findChildren(lambda x: x.roleName == 'toggle button' and x.showing and x.sensitive \
                                                                                      and x.name == 'Menu')[-1].click()
        renames = context.app.findChildren(lambda x: x.name == 'Rename' and x.showing)
    renames[0].click()
    sleep(0.5)
    typeText(name)
    context.app.findChildren(lambda x: x.showing and x.name == 'Done')[0].click()

@step('Create snapshot "{snap_name}" from machine "{vm_name}"')
def create_snapshot(context, snap_name, vm_name):
    context.execute_steps("""
        * Launch "Properties" for "%s" box
        * Press "Snapshots"
        * Add Snapshot named "%s"
        * Hit "Esc"
        """ %(vm_name, snap_name))

@step('Delete machines "{vm_name}" snapshot "{snap_name}"')
def delete_snapshot(context, vm_name, snap_name):
    context.execute_steps("""
        * Launch "Properties" for "%s" box
        * Press "Snapshots"
        """ % vm_name)

    name = context.app.findChildren(lambda x: x.name == snap_name and x.showing)[0]
    name.parent.child('Menu').click()
    delete = context.app.findChildren(lambda x: x.name == "Delete" and x.showing)[0]
    delete.click()

    context.app.findChildren(lambda x: x.name == 'Undo' and x.showing)[0].grabFocus()
    pressKey('Tab')
    pressKey('Enter')
    sleep(2)

    pressKey('Esc')

@step('Revert machine "{vm_name}" to state "{snap_name}"')
def revert_snapshot(context, vm_name, snap_name):
    context.execute_steps("""
        * Launch "Properties" for "%s" box
        * Press "Snapshots"
        """ % vm_name)

    name = context.app.findChildren(lambda x: x.name == snap_name and x.showing)[0]
    name.parent.child('Menu').click()
    revert = context.app.findChildren(lambda x: x.name == "Revert to this state" and x.showing)[0]
    revert.click()

    pressKey('Esc')
