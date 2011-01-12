#!/usr/bin/python

# aterm.py

from __future__ import with_statement
import os
import signal
import sys
import thread
import threading
import traceback

from pyterm import comm

B57600 = comm.B57600
B500000 = comm.B500000
B1000000 = comm.B1000000

Baud_rates = {
    "57600": B57600,
    "500000": B500000,
    "1000000": B1000000,
}

class terminal(object):
    thread = None
    def __init__(self, consumer = None):
        self.destinations = []
        self.listening_list = []
        self.closed = False
        if consumer:
            self.push_consumer(consumer)
            self.start()

    def __enter__(self):
        return self

    def __exit__(self, exc_type = None, exc_value = None, exc_tb = None):
        #sys.stderr.write("%s.__exit__\n" % self.name)
        self.close()
        return False

    def listening_to(self, producer):
        assert not self.closed
        self.listening_list.append(producer)

    def not_listening_to(self, producer):
        self.listening_list.remove(producer)

    def close(self):
        if not self.closed:
            for producer in self.listening_list: producer.pop_consumer(self)
            self.do_close()
            self.closed = True

    def start(self):
        #sys.stderr.write("%s: start called\n" % self.name)
        assert self.thread is None, "%s: started twice!" % self.name
        assert self.destinations, "%s: start with no push_consumer" % self.name
        self.do_start()

    def do_start(self):
        self.thread = threading.Thread(target=self.run, name=self.name)
        self.thread.setDaemon(True)
        #sys.stderr.write("%s: starting thread\n" % self.name)
        self.thread.start()

    def thread_init(self):
        pass

    def push_consumer(self, consumer):
        self.destinations.insert(0, consumer)
        consumer.listening_to(self)

    def pop_consumer(self, consumer):
        self.destinations.remove(consumer)
        consumer.not_listening_to(self)

    def run(self):
        try:
            #sys.stderr.write("%s running, pid is %d\n" %
            #                   (self.name, os.getpid()))
            self.thread_init()
            while self.destinations and not self.closed:
                #sys.stderr.write("%s: top of loop\n" % (self.name,))
                read_len = self.destinations[0].read_len
                if read_len is None:
                    data = self.read()
                    #sys.stderr.write("%s: read %r\n" % (self.name, data))
                else:
                    data = self.read(read_len)
                if not self.destinations or (not data and self.close_on_eof):
                    #sys.stderr.write("%s: 0 dests or eof, %d destinations\n" %
                    #                   (self.name, len(self.destinations)))
                    break
                #sys.stderr.write("%s: doing write\n" % (self.name,))
                self.destinations[0].write(data)
                #sys.stderr.write("%s: did write\n" % (self.name,))
        except Exception, e:
            #sys.stderr.write("%s: run caught %r\n" % (self.name, e))
            traceback.print_exc()
            if not self.thread:
                raise
        finally:
            #sys.stderr.write("%s done, %d destinations, closed %r\n" %
            #                  (self.name, len(self.destinations), self.closed))
            self.close()
            if self.thread is not None:
                #sys.stderr.write("exiting thread %s\n" % self.name)
                #self.thread.exit()
                #sys.stderr.write("You should not see this!\n")

class usb(terminal):
    r'''Reads and writes to USB (Arduino).

    This is run in the main thread; so the main thread waits on output from
    the Arduino.
    '''
    close_on_eof = False
    read_len = None
    def __init__(self, devnum = 0, timeout = 0, baud = B57600, crtscts = False,
                 format_strings = None):
        super(usb, self).__init__()
        if baud is None:
            self.fd = comm.open(devnum, timeout, crtscts=crtscts)
        else:
            self.fd = comm.open(devnum, timeout, baud = baud, crtscts=crtscts)
        self.name = "usb%d" % devnum
        self.format_strings = format_strings

    def do_start(self):
        try:
            self.run()  # <== close on KeyboardInterrupt done here
        except KeyboardInterrupt:
            #sys.stderr.write("%s: caught KeyboardInterrupt\n" % self.name)
            pass

    def read(self, n=1):
        data = os.read(self.fd, n)
        if len(data) > 0 and self.format_strings:
            key = ord(data[0])
            fs = self.format_strings[key]
            while fs.size > len(data) - 1:
                data += os.read(self.fd, fs.size - (len(data) - 1))
            assert len(data) - 1 == fs.size, \
                   "key %d: expected len %d, got %d" % \
                     (key, fs.size, len(data) - 1)
            return fs.format(data[1:])
        else:
            return data

    def write(self, s):
        while s:
            l = os.write(self.fd, s)
            s = s[l:]

    def do_close(self):
        os.close(self.fd)

class linux_terminal(terminal):
    r'''Reads and writes to the Linux terminal.

    This is run in its own thread; so its own thread waits on input from the
    Linux terminal.
    '''
    close_on_eof = True
    read_len = 1
    name = "linux_terminal"
    def read(self):
        #sys.stderr.write("linux_terminal read called\n")
        try:
            ans = raw_input() + '\n'
        except EOFError:
            ans = ''
        #sys.stderr.write("linux_terminal read: %r\n" % (ans,))
        return ans

    def write(self, s):
        sys.stdout.write(escape(s.replace('\r', '')))
        #sys.stdout.write(escape(s))

    def do_close(self):
        #sys.stderr.write("%s: interrupting main\n" % self.name)
        os.kill(os.getpid(), signal.SIGINT)

def escape(s):
    ans = ''
    for c in s:
        n = ord(c)
        if (n < 0x20 or n > 127) and c != '\n': ans += '\\' + hex(n)[1:]
        else: ans += c
    return ans

class shell(terminal):
    read_len = None
    name = "command_processor"
    def __init__(self, linux, arduino, **commands):
        super(shell, self).__init__()
        self.linux = linux
        self.arduino = arduino
        self.commands = commands

    def write(self, s):
        r'''This is run in the Linux terminal thread.

        Commands are run in the Linux terminal thread too.
        '''
        if s[0] != '!': self.arduino.write(s)
        else:
            if '>' in s:
                out = open(s[s.index('>')+1:].strip(), 'w')
                s = s[:s.index('>')]
                close = True
            else:
                out = self.linux
                close = False
            args = s[1:].split()
            if args[0] not in self.commands:
                sys.stderr.write("Error: unknown command '%s'\n" % args[0])
                if close: out.close()
            else:
                #sys.stderr.write("%s: running command '%s'\n" %
                #                   (self.name, args[0]))
                #sys.stderr.write("%s: fn is %r\n" % 
                #                   (self.name, self.commands[args[0]]))
                #sys.stderr.write("%s: out is %r\n" % (self.name, out))
                #sys.stderr.write("%s: close is %r\n" % (self.name, close))
                #sys.stderr.write("%s: self.arduino is %r\n" % 
                #                   (self.name, self.arduino))
                #sys.stderr.write("%s: args is %r\n" % (self.name, args[1:]))

                self.commands[args[0]](out, close, self.arduino, *args[1:])
                #sys.stderr.write("%s: command returned\n" % self.name)

class format_string(object):
    r'''This is a format string for output from the Arduino.

    The args are tuples of type and length, where type is either "signed" or
    "unsigned".

        >>> fs = format_string("hi mom\n")
        >>> fs.size
        0
        >>> fs.format('')
        'hi mom\n'
        >>> fs = format_string("s1=%d, s2=%d, s4=%d, u1=%d, u2=%d, u4=%d\n",
        ...                    ('signed', 1),
        ...                    ('signed', 2),
        ...                    ('signed', 4),
        ...                    ('unsigned', 1),
        ...                    ('unsigned', 2),
        ...                    ('unsigned', 4))
        >>> fs.size
        14
        >>> fs.format('\xff\x12\x34\xff\xff\xff\xfe\xff\x12\x34\xff\xff\xff\xfe')
        's1=-1, s2=4660, s4=-2, u1=255, u2=4660, u4=4294967294\n'
    '''
    def __init__(self, format_str, *args):
        r'''args are ('signed'|'unsigned', length)
        '''
        self.format_str = format_str
        self.args = args
        self.size = sum(arg[1] for arg in args)

    def format(self, data):
        data_start = 0
        args = []
        for type, length in self.args:
            num = ord(data[data_start])
            if type == 'signed':
                if num & 0x80: num -= 256
            for byte in data[data_start + 1:data_start + length]:
                num = (num << 8) | ord(byte)
            args.append(num)
            data_start += length
        return self.format_str % self.fix_args(args)

    def fix_args(self, args):
        return tuple(args)

def start(devnum = 0, timeout = 0, baud = B57600, crtscts = False,
          commands = None, format_strings = None):
    with usb(devnum, timeout, baud, crtscts, format_strings) as arduino:
        with linux_terminal() as linux:
            arduino.push_consumer(linux)
            #sys.stderr.write("did arduino.push_consumer(linux)\n")
            if commands is None:
                sh = shell(linux, arduino)
            else:
                sh = shell(linux, arduino, **commands)
            #sys.stderr.write("created shell\n")
            linux.push_consumer(sh)
            #sys.stderr.write("did linux.push_consumer(sh)\n")
            linux.start()
            #sys.stderr.write("did linux.start()\n")
            arduino.start()
            #sys.stderr.write("aterm.start done\n")

def import_module(module_path):
    module = __import__(module_path)
    for name in module_path.split('.')[1:]:
        module = getattr(module, name)
    return module

def run(timeout = None, baud = None, crtscts = None, commands = None,
        format_strings = None, usage = None):
    from optparse import OptionParser
    parser = OptionParser()
    if usage is not None:
        parser.set_usage(usage)
    parser.add_option("-d", "--devnum", type="int", default=0,
                      help="device number (what comes after /dev/ttyUCB)")
    if timeout is None:
        parser.add_option("-t", "--timeout", type="int", default=0,
                          metavar="DECISEC",
                          help="timeout for USB read")
    if baud is None:
        parser.add_option("-b", "--baud", default="57600", metavar="BAUDRATE",
                          choices=("57600", "500000", "1000000"),
                          help="choices: 57600 (default), 500000, 1000000")
    if crtscts is None:
        parser.add_option("-f", "--flow-control", dest="crtscts",
                          action="store_true", default=False,
                          help="Enable hardware flow control (CTS)")

    if commands is None:
        parser.add_option("-c", "--commands", metavar="PYTHON.MODULE",
                          callback=get_commands,
                          help="Python commands module")

    options, args = parser.parse_args()
    if timeout is not None: options.timeout = timeout
    if baud is not None: options.baud = str(baud)
    if crtscts is not None: options.crtscts = crtscts
    if commands is not None: options.commands = commands, format_strings

    start(options.devnum, options.timeout, Baud_rates[options.baud],
          options.crtscts, options.commands[0], options.commands[1])

def get_commands(option, opt, module_path, parser):
    try:
        module = import_module(module_path)
    except (ImportError, AttributeError):
        raise optparser.OptionValueError("Python module %r not found" %
                                           (module_path,))
    try:
        return module.Commands, module.Format_strings
    except AttributeError:
        raise optparser.OptionValueError(
                "Python module %r does not have 'Commands' attribute" %
                  (module_path,))

if __name__ == "__main__":
    run()

