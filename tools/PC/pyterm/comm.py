# comm.py

r'''Sets up the USB serial to the Arduino.
'''

from __future__ import with_statement

import sys
import os
import termios

B57600 = termios.B57600
# These aren't defined in termios, but are in /usr/include/bits/termios.h:
B500000 = 010005
B1000000 = 010010

# Seems like I'd want:
#   <none> ... but INPCK was set ???
iflags = ('IGNBRK', 'BRKINT', 'IGNPAR', 'PARMRK', 'INPCK', 'ISTRIP', 'INLCR',
          'IGNCR', 'ICRNL', 'IUCLC', 'IXON', 'IXANY', 'IXOFF', 'IMAXBEL',
         #'IUTF8',
)

# Seems like I'd want:
#   <none>
oflags = ('OPOST', 'OLCUC', 'ONLCR', 'OCRNL', 'ONOCR', 'ONLRET', 'OFILL',
          'NLDLY', 'CRDLY', 'TABDLY', 'BSDLY', 'VTDLY', 'FFDLY',
)

# Seems like I'd want:
#    CBAUD = 57600 (ispeed and ospeed == termios.B57600)
#    CS8 (CSIZE == CS8)
#    HUPCL ? (causes next open to do a reset)
#    CREAD ?? ("enable receiver" -- was set)
#    CLOCAL ?? ("ignore modem control lines" -- was set)
#    CRTSCTS ?? ("enable RTS/CTS (hardware) flow control" -- was not set)
cflags = ('CBAUD', 'CSIZE', 'CSTOPB', 'CREAD', 'PARENB', 'PARODD', 'HUPCL',
          'CLOCAL',
         #'LOBLK',
          'CIBAUD',
         #'CMSPAR',
          'CRTSCTS',
)

# Seems like I'd want:
#   <none>
lflags = ('ISIG', 'ICANON', 'XCASE', 'ECHO', 'ECHOE', 'ECHOK', 'ECHONL',
          'ECHOCTL', 'ECHOPRT', 'ECHOKE',
         #'DEFECHO',
         #'FLUSH0',
          'NOFLSH',
          'TOSTOP', 'PENDIN', 'IEXTEN',
)

# Seems like I'd want:
#   wait forever:
#     VMIN = 1
#     VTIME = 0 (tenths of sec)
#   or timed wait:
#     VMIN = 0
#     VTIME = 3 (tenths of sec)
cc_indices = ('VINTR', 'VQUIT', 'VERASE', 'VKILL', 'VEOF', 'VMIN', 'VEOL',
              'VTIME', 'VEOL2', 'VSWTCH', 'VSTART', 'VSTOP', 'VSUSP',
              #'VDSUSP',
              'VLNEXT', 'VWERASE', 'VREPRINT', 'VDISCARD',
              #'VSTATUS',
)


class osclosing(object):
    r'''A context manager that call os.close on a file descriptor (fd).
    '''
    def __init__(self, fd):
        self.fd = fd

    def __enter__(self):
        return self.fd

    def __exit__(self, exc_type = None, exc_value = None, exc_tb = None):
        os.close(self.fd)
        return False    # reraise exception (if any)


def translate(names):
    return (dict((name, getattr(termios, name)) for name in names),
            dict((getattr(termios, name), name) for name in names))

# {flags_name: (settings_index, ({flag_name: bit_mask}, {bit_mask: flag_name}))}
translations = {
    'iflags':     (0, translate(iflags)),
    'oflags':     (1, translate(oflags)),
    'cflags':     (2, translate(cflags)),
    'lflags':     (3, translate(lflags)),
    'cc_indices': (6, translate(cc_indices)),
}

def test(fd):
    print ["iflag", "oflag", "cflag", "lflag", "ispeed", "ospeed", "cc"]
    settings = termios.tcgetattr(fd)
    print settings
    print_flags(settings, 'iflags')
    print_flags(settings, 'oflags')
    print_flags(settings, 'cflags')
    print_flags(settings, 'lflags')
    print_flags2(settings, 'cc_indices')

def print_flags(settings, flags_name):
    r'''Prints bit mapped settings for flags_name to sys.stdout on one line.
    '''
    bits = settings[translations[flags_name][0]]
    first = True
    print "%s: " % flags_name,
    for bit_mask, name in translations[flags_name][1][1].iteritems():
        bit_tuple = make_bit_tuple(bit_mask)
        if len(bit_tuple) == 1:
            if bit_mask & bits:
                if first:
                    print name, 
                    first = False
                else:
                    print ',', name, 
        else:
            num = bit_mask & bits
            num >>= bit_tuple[-1]
            if first:
                first = False
            else:
                print ',',
            print "%s = %d" % (name, num),
    print

def make_bit_tuple(mask):
    r'''Returns a tuple of the bit numbers set in `mask`.

    The bit numbers are in descending order.

        >>> make_bit_tuple(0x12)
        (4, 2)

    Only used by print_flags, above.
    '''
    if mask < 0: mask += 2*(sys.maxint + 1)
    ans = []
    bit_num = 0
    while mask:
        if (1 << bit_num) & mask:
            ans.append(bit_num)
            mask &= ~(1 << bit_num)
        bit_num += 1
    ans.reverse()
    return tuple(ans)

def print_flags2(settings, flags_name):
    r'''Prints multi-byte settings for flags_name to sys.stdout on one line.
    '''
    bytes = settings[translations[flags_name][0]]
    first = True
    print "%s: " % flags_name,
    for byte_num, name in translations[flags_name][1][1].iteritems():
        byte = bytes[byte_num]
        if isinstance(byte, str): byte = ord(byte)
        if byte:
            if first:
                first = False
            else:
                print ',',
            print "%s=%d" % (name, byte),
    print

def stty(fd, timeout = 0, baud = B57600,
         hupcl = True, cread = True, clocal = False, crtscts = False,
         inpck = False):
    r'''Sets stty options on `fd`.

    timeout      - in tenths of a second
    hupcl=True   - causes next open to do a reset
    cread=False  - doesn't seem to make any difference
    clocal=False - doesn't seem to make any difference
    crtscts=True - hangs on read (even if clocal=False and/or cread=False).
    inpck=True   - doesn't seem to make any difference.
    '''

    # ["iflag", "oflag", "cflag", "lflag", "ispeed", "ospeed", "cc"]
    cc_values = [chr(0)] * termios.NCCS
    if timeout == 0:
        cc_values[termios.VMIN] = 1
        cc_values[termios.VTIME] = 0
    else:
        cc_values[termios.VMIN] = 0
        cc_values[termios.VTIME] = timeout
    settings = [termios.INPCK if inpck else 0,  # iflag
                0,                              # oflag
                baud | termios.CS8 |            # cflag
                  (termios.HUPCL if hupcl else 0) |
                  (termios.CREAD if cread else 0) |
                  (termios.CLOCAL if clocal else 0) |
                  (termios.CRTSCTS if crtscts else 0),
                0,                              # lflag
                baud,                           # ispeed
                baud,                           # ospeed
                cc_values                       # cc
    ]
    termios.tcsetattr(fd, termios.TCSANOW, settings)

def open(devnum=0, timeout = 0, baud = B500000,
         hupcl = True, cread = True, clocal = False, crtscts = False,
         inpck = False):
    r'''Open and initialize /dev/ttyUSB<devnum>.
    '''
    fd = os.open('/dev/ttyUSB' + repr(devnum), os.O_RDWR | os.O_NOCTTY)
    try:
        stty(fd, timeout=timeout, baud=baud, hupcl=hupcl, cread=cread,
                 clocal=clocal, crtscts=crtscts, inpck=inpck)
        return fd
    except BaseException:
        os.close(fd)
        raise

def readline(fd, strip_nulls=False):
    r'''Read one line, discarding the terminating \n.

    Ignores nulls if strip_nulls is True.
    '''
    num_nulls = 0
    line = os.read(fd, 1)
    if strip_nulls:
        while ord(line) == 0:
            num_nulls += 1
            line = os.read(fd, 1)
    while line[-1] != '\n':
        c = os.read(fd, 1)
        if strip_nulls:
            while ord(c) == 0:
                num_nulls += 1
                c = os.read(fd, 1)
        line += c
    if num_nulls:
        print 'got', num_nulls, 'null chars'
    return line[:-1]

def write(fd, s):
    r'''Write string `s` to `fd`, ensuring that the whole string is taken.
    '''
    while s:
        l = os.write(fd, s)
        s = s[l:]

def run(devnum = 0, command = 'h'):
    r'''Open device and send a single command.

    Loops copying output from device to sys.stdout.
    '''
    with osclosing(open(devnum)) as f:
        write(f, command)
        sys.stdout.write("sent command: %s\n" % command)
        while True:
            sys.stdout.write(os.read(f, 1))

def repeat(devnum = 0, s = '\x55', **kws):
    r'''Repeatedly send `s` to device as fast as possible.

    `kws` are open options.  Does not display results from device.
    '''
    with osclosing(open(devnum, **kws)) as f:
        while True:
            write(f, s)

def cycle(devnum = 0, **kws):
    r'''Repeatedly send all characters (0x00 - 0xff) to device as fast as
    possible.

    Does not display results from device.
    '''
    s = ''.join(chr(i) for i in range(256))
    print "cycling", repr(s)
    repeat(devnum, s, **kws)

def repeat_file(filename, devnum = 0):
    r'''Repeatedly send the contents of `filename` to device as fast as 
    possible.

    Does not display results from device.
    '''
    with file(filename) as f:
        data = f.read()
    repeat(devnum, data, crtscts = True)
