# sign.py

import itertools

s = (
    "  XXX  X  XXX   ",
    "  X   X X  X    ",
    "  XX  XXX  X    ",
    "  X   X X  X    ",
    "  XXX X X  X    ",
    "                ",
    "     X  XXX     ",
    "    X X  X      ",
    "    XXX  X      ",
    "    X X  X      ",
    "                ",
    " XXX XXX XXX  XX",
    "  X  X X X   X  ",
    "  X  X X XX   X ",
    "X X  X X X     X",
    " XX  XXX XXX XX ",
)

E = (
    "            ",
    "XXXXXXXXXX  ",
    "XXXXXXXXXX  ",
    "XX          ",
    "XX          ",
    "XX          ",
    "XX          ",
    "XXXXXXX     ",
    "XXXXXXX     ",
    "XX          ",
    "XX          ",
    "XX          ",
    "XX          ",
    "XXXXXXXXXX  ",
    "XXXXXXXXXX  ",
    "            ",
)

A = (
    "            ",
    "  XXXXXX    ",
    " XXXXXXXX   ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XXXXXXXXXX  ",
    "XXXXXXXXXX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "            ",
)

T = (
    "            ",
    "XXXXXXXXXX  ",
    "XXXXXXXXXX  ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "            ",
)

J = (
    "            ",
    "XXXXXXXXXX  ",
    "XXXXXXXXXX  ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "    XX      ",
    "XX  XX      ",
    "XX  XX      ",
    "XXXXXX      ",
    " XXXX       ",
    "            ",
)

O = (
    "            ",
    " XXXXXXXX   ",
    "XXXXXXXXXX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XX      XX  ",
    "XXXXXXXXXX  ",
    " XXXXXXXX   ",
    "            ",
)

S = (
    "            ",
    " XXXXXXXX   ",
    "XXXXXXXXXX  ",
    "XX      XX  ",
    " XX         ",
    "  XX        ",
    "   XX       ",
    "    XX      ",
    "     XX     ",
    "      XX    ",
    "       XX   ",
    "        XX  ",
    "XX      XX  ",
    "XXXXXXXXXX  ",
    " XXXXXXXX   ",
    "            ",
)

SP = (
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
    "            ",
)

def makenum(column):
    r'''Makes a 16-bit int from the chars in column (MSB first).

        >>> hex(makenum((' ', 'X', ' ', 'X')))
        '0x5'
    '''
    return int(''.join(('0' if c == ' ' else '1') for c in column), 2)

def make_pages(s, start = 0):
    r'''Returns two sets of 8 16-bit ints for the left and right pages.

        >>> make_pages(("XX  XX  XX  XX  ", "                "))
        ((2, 2, 0, 0, 2, 2, 0, 0), (0, 0, 2, 2, 0, 0, 2, 2))
    '''
    columns = tuple(makenum(column) for column in zip(*s)[start:start+16])
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

def make_sign(s, start = 0):
    left_page, right_page = tuple(convert_page(p) for p in make_pages(s, start))
    zero_page = chr(0) * 16
    return left_page + zero_page * 24 + right_page + zero_page * 24

def combine(*chars):
    return tuple(''.join(lines) for lines in zip(*chars))

def make_banner(s, inc = 1):
    return ''.join(make_sign(s, i) for i in range(0, len(s[0])-16, inc))
