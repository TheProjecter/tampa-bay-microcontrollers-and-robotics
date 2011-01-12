# render.py

from __future__ import division

import itertools

import shape

Lights = tuple(shape.point.semi_polar(ro * (360/50), 7.5 - theta, z)
               for theta in range(8)  # distance from center
               for ro in range(50)    # step (=> angle)
               for z in range(16))    # height

def to_file(f, bytes):
    for b in bytes:
        f.write(chr(b))

def frame(*shapes):
    return to_binary(any(light in shape for shape in shapes)
                     for light in Lights)

def to_binary(bools):
    r'''Converts 12,800 boolean values into 800 bytes for one image.
    '''
    return (line_to_word(line) for line in grouper(8, bools))

def line_to_word(line):
    r'''Converts 8 boolean values into one byte (as an int).

    The first boolean is the LSB.

        >>> hex(line_to_word((0, 0, 0, 1,  0, 0, 1, 0)))
        '0x48'
    '''
    return int((''.join('1' if b else '0' for b in line[::-1])), 2)

def grouper(n, iterable, fillvalue=None):
    r'''Groups iterable n at a time.

        >>> tuple(grouper(3, 'ABCDEFG', 'x'))
        (('A', 'B', 'C'), ('D', 'E', 'F'), ('G', 'x', 'x'))
    '''
    args = [iter(iterable)] * n
    return itertools.izip_longest(fillvalue=fillvalue, *args)

