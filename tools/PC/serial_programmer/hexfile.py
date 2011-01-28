# hexfile.py

import operator
import itertools

def from_hex(s):
    r'''Converts s to int as hex.

        >>> hex(from_hex('12'))
        '0x12'
        >>> hex(from_hex('1234'))
        '0x1234'
    '''
    return int(s, 16)

def check_sum(s):
    r'''Returns check sum of s taken as hex bytes.

        >>> hex(check_sum('123456'))
        '0x9c'
    '''
    return sum(from_hex(s[i:i+2]) for i in range(0, len(s), 2)) % 256

def decode(filename):
    r'''Decode .hex file, generating addr, data pairs.

    The .hex format is (all data in hex):
        :LLAAAATTDD..CC

        LL = length 
        AAAA = address
        TT = rec type (00 for data, 01 for EOF)
        DD... = data (var length)
        CC = check sum
    '''
    with open(filename) as f:
        for lineno, line in enumerate(f, 1):
            line = line.rstrip()
            #print len(line), repr(line)
            if line[0] != ':':
                raise ValueError("{0}({1}): Invalid line, missing ':'"
                                 .format(filename, lineno))
            data_len = from_hex(line[1:3])
            #print "data_len", data_len
            if 2*data_len + 11 != len(line):
                raise ValueError("{0}({1}): Incorrect data length"
                                 .format(filename, lineno))
            addr = from_hex(line[3:7])
            rec_type = from_hex(line[7:9])
            if check_sum(line[1:]) != 0x00:
                raise ValueError("{0}({1}): Incorrect check sum"
                                 .format(filename, lineno))
            if rec_type == 1: break
            if rec_type != 0:
                raise ValueError("{0}({1}): Unknown rec type, {2}"
                                 .format(filename, lineno, line[7:9]))
            data = line[9:-2]
            yield addr, data

def read_hex(filename):
    r'''Reads .hex file.

    Returns [[address, string], ...] concatenating all data destined for
    consecutive addresses.
    '''
    next_addr = None
    ans = []
    for addr, data in decode(filename):
        if addr == next_addr:
            ans[-1][1] += data
        else:
            ans.append([addr, data])
        next_addr = addr + len(data) // 2
    ans.sort(key=operator.itemgetter(0))
    return ans

if __name__ == "__main__":
    import sys
    print read_hex(sys.argv[1])

