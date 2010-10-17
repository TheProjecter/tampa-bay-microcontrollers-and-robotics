# sign.py

import itertools

s = (
    " XXXX  XX  XXXXX",
    " X    X  X   X  ",
    " XXX  XXXX   X  ",
    " X    X  X   X  ",
    " XXXX X  X   X  ",
    "                ",
    "     XX  XXXXX  ",
    "    X  X   X    ",
    "    XXXX   X    ",
    "    X  X   X    ",
    "                ",
    "XXXX XXX XXX  XX",
    "  X  X X X   X  ",
    "  X  X X XX   X ",
    "X X  X X X     X",
    " XX  XXX XXX XX ",
)

def makenum(column):
    r'''Makes a 16-bit int from the chars in column (MSB first).

        >>> hex(makenum((' ', 'X', ' ', 'X')))
        '0x5'
    '''
    return int(''.join(('0' if c == ' ' else '1') for c in column), 2)

def make_pages(s):
    r'''Returns two sets of 8 16-bit ints for the left and right pages.

        >>> make_pages(("XX  XX  XX  XX  ", "                "))
        ((2, 2, 0, 0, 2, 2, 0, 0), (0, 0, 2, 2, 0, 0, 2, 2))
    '''
    columns = tuple(makenum(column) for column in zip(*s))
    left_page = columns[:8]
    right_page = columns[15:7:-1]
    return left_page, right_page

def convert_page(page):
    r'''A page is made up of 8 16-bit ints.

    Returns a string containing the binary data.

        >>> convert_page((0x4241, 0x4443, 0x4645, 0x4847, 0x4A49, 0x4C4B,
        ...               0x4E4D, 0x504F))
        'ABCDEFGHIJKLMNOP'
    '''
    return ''.join(itertools.chain(*tuple((chr(i & 0xff), chr(i >> 8))
                                          for i in page)))

def make_sign(s):
    left_page, right_page = tuple(convert_page(p) for p in make_pages(s))
    zero_page = chr(0) * 16
    return left_page + zero_page * 24 + right_page + zero_page * 24

