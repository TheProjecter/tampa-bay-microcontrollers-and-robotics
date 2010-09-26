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
    comm.repeat(devnum, data, crtscts = True)
