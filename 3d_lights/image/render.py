# render.py

from __future__ import division

import itertools

import shape

Debug = True

First_offset = 0.2      # offset to light closest to center

Last_offset = 7 + First_offset

Multiples = tuple(int(Last_offset // (Last_offset - radius))
                  for radius in range(8))  # distance from center

print "Multiples", Multiples

Lights = tuple(shape.point.semi_polar(ro * (360/50), Last_offset - radius, z)
               if ro % Multiples[radius] == 0
               else None
               for ro in range(50)    # step (=> angle)
               for radius in range(8)  # distance from center
               for z in range(16))    # height

def by_page(frame):
    r'''Generates frame by pages of 128.

        >>> pages = tuple(by_page(z for ro in range(50)
        ...                         for radius in range(8)
        ...                         for z in range(16)))
        >>> len(pages)
        50
        >>> for p in pages[1:]:
        ...     assert p == pages[0]
    '''
    return grouper(8*16, frame)

def by_row(page):
    r'''Generates page by rows of 8.

    The rows are generated from the bottom up.

        >>> for row in by_row(z for radius in range(8)
        ...                     for z in range(16)):
        ...     print row[0],
        ...     for col in row[1:]:
        ...         assert col == row[0]
        0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
    '''
    return zip(*grouper(16, page))

def to_file(f, bytes):
    for b in bytes:
        f.write(chr(b))

def frame(*shapes):
    return to_binary(any(light in shape for shape in shapes)
                     for light in Lights)

def to_binary(bools):
    r'''Converts 6,400 boolean values into 800 bytes for one image.
    '''
    if Debug:
        bools = tuple(bools)
        assert len(bools) == 6400
        for page in by_page(bools):
            for row in tuple(by_row(page))[::-1]:
                for col in tuple(row)[::-1]:
                    print 'X ' if col else '. ',
                print
            print '*** end page ***'
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

if Debug:
    assert len(Lights) == 50 * 8 * 16
    pages = tuple(by_page(Lights))
    assert len(pages) == 50
    for p in pages:
        for i, row in enumerate(by_row(p)):
            for col in row:
                assert col is None or i == col.z
