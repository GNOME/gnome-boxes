# -*- coding: UTF-8 -*-
from dogtail.utils import isA11yEnabled, enableA11y
if isA11yEnabled() is False:
    enableA11y(True)

from time import time, sleep
from functools import wraps
from os import strerror, errno, kill, system
from signal import signal, alarm, SIGALRM, SIGKILL
from subprocess import Popen, PIPE
from behave import step
from gi.repository import GLib, Gio
import fcntl, os

from dogtail.rawinput import keyCombo, absoluteMotion, pressKey
from dogtail.tree import root
from dogtail.utils import run
from unittest import TestCase

# Create a dummy unittest class to have nice assertions
class dummy(TestCase):
    def runTest(self):  # pylint: disable=R0201
        assert True

def wait_until(my_lambda, element, timeout=30, period=0.25):
    """
    This function keeps running lambda with specified params until the result is True
    or timeout is reached
    Sample usages:
     * wait_until(lambda x: x.name != 'Loading...', context.app)
       Pause until window title is not 'Loading...'.
       Return False if window title is still 'Loading...'
       Throw an exception if window doesn't exist after default timeout

     * wait_until(lambda element, expected: x.text == expected, element, ('Expected text'))
       Wait until element text becomes the expected (passed to the lambda)

    """
    exception_thrown = None
    mustend = int(time()) + timeout
    while int(time()) < mustend:
        try:
            if my_lambda(element):
                return True
        except Exception as e:
            # If lambda has thrown the exception we'll re-raise it later
            # and forget about if lambda passes
            exception_thrown = e
        sleep(period)
    if exception_thrown:
        raise exception_thrown
    else:
        return False

class TimeoutError(Exception):
    """
    Timeout exception class for limit_execution_time_to function
    """
    pass

def limit_execution_time_to(
        seconds=10, error_message=strerror(errno.ETIME)):
    """
    Decorator to limit function execution to specified limit
    """
    def decorator(func):
        def _handle_timeout(signum, frame):
            raise TimeoutError(error_message)

        def wrapper(*args, **kwargs):
            signal(SIGALRM, _handle_timeout)
            alarm(seconds)
            try:
                result = func(*args, **kwargs)
            finally:
                alarm(0)
            return result

        return wraps(func)(wrapper)

    return decorator

class App(object):
    """
    This class does all basic events with the app
    """
    def __init__(
        self, appName, shortcut='<Control><Q>', a11yAppName=None,
            forceKill=True, parameters='', recordVideo=False):
        """
        Initialize object App
        appName     command to run the app
        shortcut    default quit shortcut
        a11yAppName app's a11y name is different than binary
        forceKill   is the app supposed to be kill before/after test?
        parameters  has the app any params needed to start? (only for startViaCommand)
        recordVideo start gnome-shell recording while running the app
        """
        self.appCommand = appName
        self.shortcut = shortcut
        self.forceKill = forceKill
        self.parameters = parameters
        self.internCommand = self.appCommand.lower()
        self.a11yAppName = a11yAppName
        self.recordVideo = recordVideo
        self.pid = None

        # a way of overcoming overview autospawn when mouse in 1,1 from start
        pressKey('Esc')
        absoluteMotion(100, 100, 2)

        # attempt to make a recording of the test
        if self.recordVideo:
            keyCombo('<Control><Alt><Shift>R')

    def isRunning(self):
        """
        Is the app running?
        """
        if self.a11yAppName is None:
            self.a11yAppName = self.internCommand

        # Trap weird bus errors
        for attempt in xrange(0, 10):
            sleep(1)
            try:
                return self.a11yAppName in [x.name for x in root.applications()]
            except GLib.GError:
                continue
        raise Exception("10 at-spi errors, seems that bus is blocked")

    def quit(self):
        """
        Quit the app via 'Ctrl+Q'
        """
        if self.recordVideo:
            keyCombo('<Control><Alt><Shift>R')

        try:
            #os.system("pkill -9 gnome-boxes")
            keyCombo('<Ctrl><Q>')
            if self.isRunning():
                self.kill()
        except:
            pass

    def kill(self):
        """
        Kill the app via 'killall'
        """
        try:
            os.system("pkill -9 gnome-boxes")
            #keyCombo('<Alt><F4>')
        except:
            # Fall back to killall
            Popen("killall " + self.appCommand, shell=True).wait()

    def startViaCommand(self):
        """
        Start the app via command
        """
        if self.forceKill and self.isRunning():
            self.kill()
            assert not self.isRunning(), "Application cannot be stopped"

        self.process = Popen(self.appCommand.split() + self.parameters.split(),
                             stdout=PIPE, stderr=PIPE, bufsize=0)
        self.pid = self.process.pid

        assert self.isRunning(), "Application failed to start"
        return root.application(self.a11yAppName)

    def closeViaShortcut(self):
        """
        Close the app via shortcut
        """
        if not self.isRunning():
            raise Exception("App is not running")

        keyCombo(self.shortcut)
        assert not self.isRunning(), "Application cannot be stopped"

def non_block_read(output):
    fd = output.fileno()
    fl = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
    try:
        return output.read()
    except:
        return ""

@step(u'Make sure that {app} is running')
def ensure_app_running(context, app):
    context.app = context.app_class.startViaCommand()
