#!/usr/bin/python

from __future__ import unicode_literals
import libvirt
from time import sleep
from general import libvirt_domain_get_val, libvirt_domain_get_context

def libvirt_domain_get_install_state(title):
    state = None

    conn = libvirt.openReadOnly(None)
    doms = conn.listAllDomains()
    for dom in doms:
        try:
            dom0 = conn.lookupByName(dom.name())
            # Annoyiingly, libvirt prints its own error message here
        except libvirt.libvirtError:
            print("Domain %s is not running" % name)
        ctx = libvirt_domain_get_context(dom0)

        if libvirt_domain_get_val(ctx, "/domain/title") == title:
            return libvirt_domain_get_val(ctx, "/domain/metadata/*/os-state")

    return None

@step('Installation of "{machine}" is finished in "{max_time}" minutes')
def check_finished_installation(context, machine, max_time):
    minutes = 0
    state = None
    while minutes < max_time:
        state = libvirt_domain_get_install_state(machine)
        if state == 'installed':
            break
        else:
            sleep(60)

    assert state == 'installed', "%s is not installed but still in %s after %s minutes" %(machine, state, max_time)
