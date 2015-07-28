# -*- coding: UTF-8 -*-

from __future__ import unicode_literals
from behave import step
from dogtail.rawinput import typeText
from dogtail.predicate import GenericPredicate
from time import sleep
from utils import get_showing_node_name

@step('Create new box "{name}" from "{item}" menuitem')
def create_machine_from_menuitem(context, name, item):
    """
    Create new box, wait till it finishes and save its IP
    """
    context.execute_steps(u"""
        * Create new box from menu "%s"
        * Press "Create"
        * Wait for "sleep 1" end
        * Hit "Enter"
        * Wait for "sleep 1" end
        * Hit "Enter"
        * Wait for "sleep 1" end
        * Hit "Enter"
        * Save IP for machine "%s"
        * Press "back" in "%s" vm
        """ %(item, name, name))

@step('Create new box "{name}"')
def create_machine(context, name):
    """
    Same as create_machine_from_menuitem except it assumes menu item and created box to have the same name.
    """
    context.execute_steps(u"""
        * Create new box "%s" from "%s" menuitem
        """ %(name, name))

@step('Create new box from file "{location}"')
def create_new_vm_via_file(context, location):
    path = location.split('/')
    context.app.child('New').click()
    context.app.child('Continue').click()
    context.app.child('Select a file').click()

    for item in path:
        context.app.child(item).click()
    context.app.child('Open').click()

@step('Create new box from url "{url}"')
def create_new_vm_via_url(context, url):
    context.app.child('New').click()
    context.app.child('Continue').click()
    context.app.child('Enter URL').click()

    typeText(url)
    context.app.child('Continue').click()

    if url.find('http') != -1:
        half_minutes = 0
        while half_minutes < 120:
            half_minutes += 1
            if context.app.findChild(
                GenericPredicate(name='Choose express install to automatically '
                                      'preconfigure the box with optimal settings.'),
                retry=False,
                requireResult=False):
                return
            create = context.app.child('Create')
            if create.sensitive and create.showing:
                create.click()
                break
            else:
                sleep(30)

@step('Create new box from menu "{sys_name}"')
def create_new_vm_from_menu(context, sys_name):
    context.app.child('New').click()
    get_showing_node_name(sys_name, context.app).click()

@step('Import machine "{name}" from image "{location}"')
def import_image(context, name, location):
    context.execute_steps(u"""
        * Create new box from file "%s"
        * Press "Create"
        * Save IP for machine "%s"
        """ %(location, name))

@step('Initiate new box "{name}" installation from "{item}" menuitem')
def create_machine_from_menuitem_no_wait(context, name, item):
    """
    Initiate new box installation but don't save its IP nor wait for it to be ready
    """
    context.execute_steps(u"""
        * Create new box from menu "%s"
        * Press "Create"
        * Wait for "sleep 1" end
        * Hit "Enter"
        * Wait for "sleep 1" end
        * Hit "Enter"
        * Press "back" in "%s" vm
        """ %(item, name))

@step('Initiate new box "{name}" installation')
def create_machine_no_wait(context, name):
    """
    Same as create_machine_from_menuitem_no_wait except it assumes menu item and created box to have the same name.
    """
    context.execute_steps(u"""
        * Initiate new box "%s" installation from "%s" menuitem
        """ %(name, name))
