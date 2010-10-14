#!/usr/bin/python

# driver.py

import os
import sys

sys.path.insert(0,
    os.path.abspath(
        os.path.join(
        os.path.dirname(__file__),
        '../../tools/PC')))

from pyterm import aterm, commands

Sync_char = chr(0xD8);
Esc_char = chr(0x27);

def escape(data):
    return data.replace(Esc_char, Esc_char + Esc_char) \
               .replace(Sync_char, Esc_char + Sync_char)

def escape_file(filename):
    with open(filename) as f:
        data = f.read()
    print "file length is", len(data)

    if len(data) > 800:
        assert len(data) % 800 == 0, "file length not multiple of 800"

    ans = []
    for i in range(0, len(data), 800):
        if len(data) - i < 800:
            assert (len(data) - i) % 16 == 0, "file length not multiple of 16"
            assert 800 % (len(data) - i) == 0, "800 not multiple of file length"
            piece = (800 // (len(data) + i)) * data[i:];
            assert len(piece) == 800
        else:
            piece = data[i:i+800]
        ans.append(Sync_char + escape(piece))

    data = ''.join(ans)
    print "escaped length is", len(data)
    return data

def file_once(filename, devnum = 0):
    data = escape_file(filename)
    with comm.osclosing(comm.open(devnum, **kws)) as f:
        comm.write(f, data)

def repeat_file(filename, devnum = 0):
    data = escape_file(filename)
    comm.repeat(devnum, data, crtscts = True)

@commands.command("%(name)s filename")
def show_once(output, close_output, arduino, filename):
    try:
        data = escape_file(filename)
        arduino.write(data)
    finally:
        if close_output: output.close()

@commands.command("%(name)s filename")
def show_forever(output, close_output, arduino, filename):
    try:
        data = escape_file(filename)
        while True:
            arduino.write(data)
    finally:
        if close_output: output.close()

Commands = {
    "show_once": show_once,
    "show_forever": show_forever,
    "help": commands.help,
}

# Needed by help command...
commands.Commands = Commands

class format_rps(aterm.format_string):
    def fix_args(self, args):
        r'''args[0] is timer1 ticks/rev @ 4uSec/tick.
        '''
        return (250000.0/args[0], args[0]/250.0)

Format_strings = {
    1: aterm.format_string("stationary_platform: %x, %x\n",
                           ('unsigned', 1),
                           ('unsigned', 2)),
    2: aterm.format_string(
         "Incomplete_bufs=%d@%d, FE=%d@%d, DOR=%d@%d, Buf_overflows=%d@%d\n",
                           ('unsigned', 1),
                           ('unsigned', 1),
                           ('unsigned', 1),
                           ('unsigned', 1),
                           ('unsigned', 1),
                           ('unsigned', 1),
                           ('unsigned', 2),
                           ('unsigned', 1)),
    3: format_rps("RPS=%.1f, mSec/rev=%.1f\n", ('unsigned', 2)),
}

if __name__ == "__main__":
    aterm.run(baud = '500000', timeout = 0, crtscts = True,
              commands = Commands, format_strings = Format_strings)

