# driver.py

import os
import sys

sys.path.insert(0,
    os.path.abspath(
        os.path.join(
        os.path.dirname(__file__),
        '../../tools/PC')))

from pyterm import comm

Sync_char = chr(0xD8);
Esc_char = chr(0x27);

def escape(data):
    return data.replace(Esc_char, Esc_char + Esc_char) \
               .replace(Sync_char, Esc_char + Sync_char)

def repeat_file(filename, devnum = 0):
    with open(filename) as f:
        data = f.read()
    print "file length is", len(data)
    print repr(data)
    if len(data) < 800:
        assert len(data) % 16 == 0, "file length not multiple of 16"
        assert 800 % len(data) == 0, "800 not multiple of file length"
        data = (800 // len(data)) * data;
        assert len(data) == 800
    elif len(data) > 800:
        assert len(data) % 800 == 0, "file length not multiple of 800"
    data = escape(data)
    print "escaped length is", len(data)
    print repr(data)
    comm.repeat(devnum, Sync_char + data, crtscts = True)
