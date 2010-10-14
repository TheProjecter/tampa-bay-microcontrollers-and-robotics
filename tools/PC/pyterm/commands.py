# commands.py

from __future__ import division
import sys

def signed(char):
    r'''
        >>> signed(0x00)
        0
        >>> signed(0x01)
        1
        >>> signed(0x7F)
        127
        >>> signed(0xFF)
        -1
        >>> signed(0x80)
        -128
        >>> signed('\x00')
        0
        >>> signed('\x01')
        1
        >>> signed('\x7F')
        127
        >>> signed('\xFF')
        -1
        >>> signed('\x80')
        -128
    '''
    ans = ord(char) if isinstance(char, str) else char
    if ans < 128: return ans
    return ans - 256

def unsigned(signed):
    r'''
        >>> unsigned(0)
        0
        >>> unsigned(1)
        1
        >>> unsigned(127)
        127
        >>> unsigned(-1)
        255
        >>> unsigned(-128)
        128
        '''
    if signed >= 0: return signed
    return 256 + signed

def command(desc):
    r''' Function decorator for command functions.

    Argument is description to come up in help listing, with command name
    substituted for %(name)s in desc string.
    '''
    def fn_dec(fn):
        fn.description = desc
        return fn
    return fn_dec

class readers(object):
    def __init__(self, output, close_output, arduino, args = ()):
        self.output = output
        self.close_output = close_output
        self.arduino = arduino
        self.args = args
        self.producer = None
        self.buffer = ''
        self.samples_seen = 0
        try:
            arduino.push_consumer(self)
            self.do_init()
        except Exception, e:
            #sys.stderr.write("streamers.__init__: caught %r exception\n" % e)
            if self.close_output: self.output.close()
            raise

    def do_init(self):
        r'''This could send a command to the Arduino to start something.

        e.g.: self.arduino.write(<command>)
        '''
        pass

    def listening_to(self, producer):
        assert self.producer is None
        self.producer = producer

    def not_listening_to(self, producer):
        assert self.producer == producer
        self.producer = None

    def write(self, s):
        try:
            buf = self.buffer + s
            while len(buf) >= self.read_len:
                self.samples_seen += 1
                done = self.process(*(ord(x) for x in buf[:self.read_len]))
                buf = buf[self.read_len:]
                if done or self.samples_seen >= self.num_samples:
                    self.arduino.pop_consumer(self)
                    if buf:
                        self.output.write("Excess samples returned\n")
                    self.wrapup()
                    if self.close_output:
                        #sys.stderr.write("closing %s\n" % self.output.name)
                        self.output.close()
                    return
            self.buffer = buf
        except Exception, e:
            #sys.stderr.write("streamers.write: caught %r exception\n" % e)
            if self.close_output: self.output.close()
            raise

    def wrapup(self): pass


@command("%(name)s")
def help(output, close_output, arduino):
    output.write("Python commands:\n")
    for command_name in sorted(Commands.iterkeys()):
        cmd = Commands[command_name]
        output.write('  ' + cmd.description % {'name': cmd.__name__} + '\n')
    if close_output: output.close()

