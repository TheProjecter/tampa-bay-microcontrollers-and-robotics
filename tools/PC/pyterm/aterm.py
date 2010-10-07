#!/usr/bin/python

# aterm.py

from __future__ import with_statement
import os
import signal
import sys
import thread
import threading
import traceback
import comm
import commands

B57600 = comm.B57600
B500000 = comm.B500000
B1000000 = comm.B1000000

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
            if self.thread:
                traceback.print_exc()
            else:
                raise
        finally:
            #sys.stderr.write("%s done, %d destinations, closed %r\n" %
            #                  (self.name, len(self.destinations), self.closed))
            self.close()
            if self.thread is not None:
                #sys.stderr.write("exiting thread %s\n" % self.name)
                thread.exit()
                sys.stderr.write("You should not see this!\n")

class usb(terminal):
    close_on_eof = False
    read_len = None
    def __init__(self, devnum = 0, timeout = 0, baud = B57600):
        super(usb, self).__init__()
        if baud is None:
            self.fd = comm.open(devnum, timeout)
        else:
            self.fd = comm.open(devnum, timeout, baud = baud)
        self.name = "usb%d" % devnum

    def do_start(self):
        try:
            self.run()  # <== close on KeyboardInterrupt done here
        except KeyboardInterrupt:
            #sys.stderr.write("%s: caught KeyboardInterrupt\n" % self.name)
            pass

    def read(self, n):
        return os.read(self.fd, n)

    def write(self, s):
        while s:
            l = os.write(self.fd, s)
            s = s[l:]

    def do_close(self):
        os.close(self.fd)

class linux_terminal(terminal):
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

def start(devnum = 0, timeout = 0, baud = B57600):
    with usb(devnum, timeout, baud) as arduino:
        with linux_terminal() as linux:
            arduino.push_consumer(linux)
            #sys.stderr.write("did arduino.push_consumer(linux)\n")
            sh = shell(linux, arduino, **commands.Commands)
            #sys.stderr.write("created shell\n")
            linux.push_consumer(sh)
            #sys.stderr.write("did linux.push_consumer(sh)\n")
            linux.start()
            #sys.stderr.write("did linux.start()\n")
            arduino.start()
            #sys.stderr.write("aterm.start done\n")

if __name__ == "__main__":
    start()
