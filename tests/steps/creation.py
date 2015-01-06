# -*- coding: UTF-8 -*-

from behave import step
from dogtail.rawinput import typeText
from time import sleep
from utils import get_showing_node_name

@step(u'Create new box "{name}"')
def create_machine(context, name):
    """
    Create new box, wait till it finish and save IP
    """
    context.execute_steps(u"""
        * Create new box from menu "%s"
        * Press "Create"
        * Wait for "sleep 3" end
        * Hit "Enter"
        * Save IP for machine "%s"
        * Press "back" in vm
        """ %(name, name))

@step(u'Create new box from url "{url}"')
def create_new_vm_via_url(context, url):
    context.app.child('New').click()
    context.app.child('Continue').click()
    context.app.child('Enter URL').click()

    typeText(url)
    context.app.child('Continue').click()

    if url.find('http') != -1:
        half_minutes = 0
        while half_minutes < 40:
            half_minutes += 1
            create = context.app.child('Create')
            if create.sensitive and create.showing:
                create.click()
                break
            else:
                sleep(30)

@step(u'Create new box from menu "{sys_name}"')
def create_new_vm_from_menu(context, sys_name):
    context.app.child('New').click()
    context.app.child('Continue').click()
    get_showing_node_name(sys_name, context.app).click()

@step(u'Initiate new box "{name}" installation')
def create_machine_no_wait(context, name):
    """
    Initiate new box installation, no IP saved, no wait for box readines
    """
    context.execute_steps(u"""
        * Create new box from menu "%s"
        * Press "Create"
        * Wait for "sleep 3" end
        * Hit "Enter"
        * Press "back" in vm
        """ %(name))
