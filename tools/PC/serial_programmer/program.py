#!/usr/bin/python

# program.py

# Serial Programming Steps (pg 311):
#
# Power On Sequence:
# 1. Bring RESET and SCK low (and hold RESET low during programming).
# 2. Apply power
# 3. Wait 20 mSec
# 4. Send the Programming Enable instruction.
#    - Programming Enable is: AC 53 00 00
#    - if second byte (53) is not echoed back in third byte, give RESET a
#      positive pulse of at least 2 clock cycles (2 uSec) and repeat step 4
#      (unsure if step 3 wait needed here).  This will resync the serial
#      programming.
#
# Power Off Sequence:
# 1. Bring RESET high.
# 2. Disconnect power.
#
# Chip Erase (erases Flash and EEPROM):
# 1. Chip Erase
#    - AC 80 00 00
# 2. Wait 9 msec
#
# Program Flash:
# - Flash page size is 64 words (6 LSB addr bits) on ATmega168 and ATmega328P.
# - Flash programming is done one page (128 bytes) at a time (using word
#   addresses):
#   - Load Program Memory Page (for each data word in the page):
#     - 40 00 addr-6-LSB data-low-byte
#     - 48 00 addr-6-LSB data-high-byte
#   - Write Program Memory Page:
#     - 4C addr-MSB addr-LSB 00 (excluding 6-LSB)
#   - Wait 4.5 msec
#     - or continue polling with Poll command until LSB of data-out is 0.
#       - Poll Command: F0 00 00 data-out
#
# Read Memory:
# - Read High Byte Flash:     28 addr-MSB addr-LSB data-out
# - Read Low Byte Flash:      20 addr-MSB addr-LSB data-out
# - Read EEPROM:              A0 addr-MSB addr-LSB data-out
# - Read Lock Bits:           58 00       00       lock-bits-out
# - Read Signature Byte:      30 00       addr2    byte-out     (2 bit addr)
# - Read Fuse Bits:           50 00       00       data-out
# - Read Fuse High Bits:      58 08       00       data-out
# - Read Extended Fuse Bits:  50 08       00       data-out
# - Read Calibration Byte:    38 00       00       data-out
#
# Write Lock and Fuse Bytes:
# - Write Lock Bits:          AC E0       00       lock-bits
# - Write Fuse Bits:          AC A0       00       fuse-bits
# - Write Fuse High Bits:     AC A8       00       fuse-bits
# - Write Extended Fuse Bits: AC A4       00       fuse-bits
#
# Program EEPROM:
# - EEPROM page size is 4 bytes on ATmega168 and ATmega328P.
# - EEPROM can be programmed in one of two modes:
#   - One byte at a time.  An erase is done for each byte written.
#     - Write EEPROM Memory:  C0 addr-MSB addr-LSB data-in
#     - Wait 3.6 msec (or poll, see Program Flash, above)
#   - One page at a time.  I think this only works after a chip erase(?)
#     - Load EEPROM Memory Page:  C1 00       addr2    data-in (2 bit addr)
#     - Write EEPROM Memory Page: C2 addr-MSB addr-LSB 00 (2 LSBs of addr == 0)
#     - Wait 3.6 msec (or poll, see Program Flash, above)
#

import os
import contextlib

from doctest_tools import setpath
setpath.setpath(__file__, remove_first = True)

from pyterm import comm
from serial_programmer import hexfile

class Serial_programming_error(EnvironmentError):
    pass

PORTB = "25"
PINB  = "23"
DDRB  = "24"
PORTC = "28"
PINC  = "26"
DDRC  = "27"
PORTD = "2B"
PIND  = "29"
DDRD  = "2A"

def pad_hex(s, num_digits = 2):
    r'''Returns n in hex with num_digits.

        >>> pad_hex('c')
        '0c'
    '''
    return "0" * (num_digits - len(s)) + s

def to_hex(n, num_digits = 2):
    r'''Returns n in hex with num_digits.

        >>> to_hex(12)
        '0c'
    '''
    return pad_hex(hex(n)[2:], num_digits)

Binary = {
    "0": "0000",
    "1": "0001",
    "2": "0010",
    "3": "0011",
    "4": "0100",
    "5": "0101",
    "6": "0110",
    "7": "0111",
    "8": "1000",
    "9": "1001",
    "a": "1010",
    "b": "1011",
    "c": "1100",
    "d": "1101",
    "e": "1110",
    "f": "1111",
}

def to_binary(s):
    r'''Returns binary representation of s.

    S is in hex as a string.  The binary return value is also as a string.

        >>> to_binary('53')
        '0101 0011'
    '''
    return ' '.join(Binary[digit.lower()] for digit in s.replace(' ', ''))

def get_result():
    line = Arduino.readline().rstrip()
    print "result:", repr(line)
    if line.startswith("ERROR:"):
        raise Serial_programming_error(line)
    return line.lower()

def send(s):
    print "sending", s
    Arduino.write("s" + s + "\n")
    return get_result()[11:]

def send_verify(s):
    s = s.replace(' ', '').lower()
    result = send(s)
    if result[2:4] != s[0:2] or result[4:6] != s[2:4] or result[6:8] != s[4:6]:
        raise Serial_programming_error("send command did not echo")

def send_read(s):
    s = s.replace(' ', '').lower()
    result = send(s)
    if result[2:4] != s[0:2] or result[4:6] != s[2:4]:
        raise Serial_programming_error("send command did not echo")
    return result[-2:]

def poll():
    while int(send_read("F0 00 00 00"), 16) & 1: pass

def read(reg):
    r'''Read reg.

    The reg is the memory address of the register in hex as a string.

    Returns the value in hex as a string.
    '''
    reg = pad_hex(reg)
    Arduino.write("r" + reg + "\n")
    ans = get_result()[18:]
    print "read from", repr(reg), "got:", repr(ans)
    return ans

def write(reg, byte):
    r'''Write byte to reg.

    The reg is the memory address of the register.  Both reg and byte are in
    hex as strings.
    '''
    reg = pad_hex(reg)
    byte = pad_hex(byte)
    print "writing", repr(byte), "to", repr(reg)
    Arduino.write("w{0}={1}\n".format(reg, byte))
    get_result()

def set_bit(reg, bit_num):
    r'''Sets bit_num in reg.

    Bit_num is an int (0-7), and reg is in hex as a string.
    '''
    write(reg, hex(int(read(reg), 16) | (1 << bit_num))[2:])

def clr_bit(reg, bit_num):
    r'''Clears bit_num in reg.

    Bit_num is an int (0-7), and reg is in hex as a string.
    '''
    write(reg, hex(int(read(reg), 16) & ~(1 << bit_num))[2:])

def delay(msec):
    r'''Delays msec.

    msec in decimal as a string.
    '''
    print "delaying", repr(msec), "msec"
    Arduino.write("d{0}\n".format(msec))
    get_result()

def enable_programming():
    for _ in range(5):
        result = send("AC 53 00 00")
        print "enable_programming got:", result
        if result[4:6] == "53":
            return
        set_bit(PORTB, 1)  # pin 9, connected to RESET
        delay("1");
        clr_bit(PORTB, 1)
        delay("20");
    raise Serial_programming_error("Enable Programming failed")

def power_off():
    set_bit(PORTB, 1)  # pin 9, connected to RESET
    print "Power off"

def chip_erase():
    r'''Erases Flash and EEPROM.
    '''
    send_verify("AC 80 00 00")
    delay("9")

def program_flash_page(addr, s):
    r'''Program one page of flash memory.

    addr must be mod 64 and is an int.  s is in hex and must be 128 bytes.
    '''
    s = s.replace(' ', '')
    assert addr % 64 == 0
    #assert len(s) == 256
    assert len(s) % 2 == 0
    # load page
    for i in range(0, len(s), 4):
        # load low-byte
        send_verify("40 00 {0} {1}".format(to_hex(i // 4), s[i:i+2]))
        if i+4 <= len(s):
            # load high-byte
            send_verify("48 00 {0} {1}".format(to_hex(i // 4), s[i+2:i+4]))
    # write page
    send_verify("4C {0} 00".format(to_hex(addr, 4)))
    poll()

def read_flash_page(addr):
    r'''Read one page of flash memory at addr.

    addr must be mod 64 and is an int.
    '''
    assert addr % 64 == 0
    return ''.join(send_read("28" + to_hex(addr + i, 4) + "00") +
                     send_read("20" + to_hex(addr + i, 4) + "00")
                   for i in range(64))

Signatures = {
    "1e 94 06": "ATmega168A",
    "1e 94 0b": "ATmega168PA",
    "1e 95 14": "ATmega328",
    "1e 95 0f": "ATmega328P",
}

def read_configuration():
    sig, processor = read_signature_bytes()
    print "signature bytes:", sig, " is ", processor
    lock_bits = read_lock_bits()
    print "lock bits:", lock_bits
    for line in decode_bits(lock_bits, Lock_bits):
        print " ", line
    fuse_low, fuse_high, extended_fuse = read_fuses().split(',')
    print "fuse low bits:", fuse_low 
    for line in decode_bits(fuse_low, Fuse_low_bits):
        print " ", line
    print "fuse high bits:", fuse_high
    for line in decode_bits(fuse_high, Fuse_high_bits):
        print " ", line
    print "extended fuse bits:", extended_fuse
    for line in decode_bits(extended_fuse, Extended_fuse):
        print " ", line
    print "calibration:", read_calibration()

def read_signature_bytes():
    sig = "{0} {1} {2}".format(send_read("30 00 00 00"),
                               send_read("30 00 01 00"),
                               send_read("30 00 02 00"))
    return sig, Signatures[sig.lower()]

def read_lock_bits():
    return to_binary(send_read("58 00 00 00"))

def read_fuses():
    return ', '.join((to_binary(send_read("50 00 00 00")),  # fuse low bits
                      to_binary(send_read("58 08 00 00")),  # fuse high bits
                      to_binary(send_read("50 08 00 00")))) # extended fuse bits

def read_calibration():
    return send_read("38 00 00 00")

def decode_bits(bits, decoding_table):
    r'''Generates decoding text for bits.

        >>> for text in decode_bits("01000011", Fuse_low_bits):
        ...     print text
        internal 128kHz RC oscillator
        SUT 00
        clock not output to B0
        divide clock by 8
    '''
    bits = bits.replace(' ', '')
    end = 8
    for num_bits, entry in zip(decoding_table[0], decoding_table[1:]):
        yield entry[int(bits[end - num_bits:end], 2)]
        end -= num_bits

Extended_fuse = (       # only for ATmega328(P)
    (3,),
    ("reserved",
     "reserved",
     "reserved",
     "reserved",
     "BOD level min 4.1V, typ 4.3V, max 4.5V",
     "BOD level min 2.5V, typ 2.7V, max 2.9V",
     "BOD level min 1.7V, typ 1.8V, max 2.0V",
     "BOD disabled"),
)

Fuse_high_bits = (      # only for ATmega328(P)
    (1, 2, 1, 1, 1, 1, 1),
    ("boot reset vector selected", "boot reset vector not selected"),
    ("bootloader size 2048 words", "bootloader size 1024 words",
     "bootloader size 512 words",  "bootloader size 256 words"),
    ("EEPROM memory preserved through Chip Erase",
     "EEPROM memory not preserved through Chip Erase"),
    ("WDT always on", "WDT not always on"),
    ("serial program and data downloading enabled",
     "serial program and data downloading disabled"),
    ("debugWIRE enabled", "debugWIRE disabled"),
    ("external reset disabled", "external reset enabled"),
)

Fuse_low_bits = (  (4, 2, 1, 1),
    ("external clock",
     "reserved",
     "calibrated internal RC oscillator",
     "internal 128kHz RC oscillator",
     "low frequency crystal oscillator 32.768kHz watch crystal 0",
     "low frequency crystal oscillator 32.768kHz watch crystal 1",
     "full swing crystal oscillator 0.4-20MHz 0",
     "full swing crystal oscillator 0.4-20MHz 1",
     "low power crystal oscillator 0.4-0.9MHz 0",
     "low power crystal oscillator 0.4-0.9MHz 1",
     "low power crystal oscillator 0.9-3.0MHz 0",
     "low power crystal oscillator 0.9-3.0MHz 1",
     "low power crystal oscillator 3.0-8.0MHz 0",
     "low power crystal oscillator 3.0-8.0MHz 1",
     "low power crystal oscillator 8.0-16.0MHz 0",
     "low power crystal oscillator 8.0-16.0MHz 1"),

    ("SUT 00", "SUT 01", "SUT 10", "SUT 11"),

    ("clock output to B0", "clock not output to B0"),
    ("divide clock by 8", "don't divide clock by 8"),
)

Lock_bits = ( (1, 1, 1, 1, 1, 1, 1, 1),
    ("programming mode writes to flash/EEPROM/fuses disabled",
     "programming mode writes to flash/EEPROM/fuses enabled"),
    ("programming mode reads to flash/EEPROM/fuses/lock(write too) disabled",
     "programming mode reads to flash/EEPROM/fuses/lock(write too) enabled"),
    ("SPM to application disabled",
     "SPM to application enabled"),
    ("LPM in bootloader of application disabled, intr disabled in appl if"
       "intr vectors in bootloader section",
     "LPM in bootloader of application enabled, intr enabled in appl if"
       "intr vectors in bootloader section"),
    ("SPM to bootloader disabled",
     "SPM to bootloader enabled"),
    ("LPM in application of bootloader disabled, intr disabled in bootloader if"
       "intr vectors in application section",
     "LPM in application of bootloader enabled, intr enabled in bootloader if"
       "intr vectors in application section"),
    ("N/A", "N/A"),
    ("N/A", "N/A"),
)

def program_flash(filename):
    for addr, data in hexfile.read_hex(filename):
        assert addr % 128 == 0
        for i in range(0, len(data)//2, 128):
            #print "program_flash_page", addr + i // 2
            #print " ", data[i*2:i*2+256]
            program_flash_page(addr + i // 2, data[i*2:i*2+256])

def menu():
    print "e                -- enable_programming"
    print "c                -- read_configuration"
    print "r reg_addr       -- read I/O register"
    print "w reg_addr=data  -- write I/O register"
    print "f page_addr      -- read flash page"
    print "x                -- chip erase"
    print "F filename       -- program flash"
    print "q                -- quit"
    command = raw_input("? ").strip()
    if command:
        if command[0] == 'e': enable_programming()
        if command[0] == 'c': read_configuration()
        if command[0] == 'r': print "read", read(command[1:].strip())
        if command[0] == 'w': write(*command[1:].split('='))
        if command[0] == 'q': return False
        if command[0] == 'f':
            addr = int(command[1:].strip(), 16)
            data = read_flash_page(addr)
            for i in range(0, len(data) // 4, 8):
                print hex(addr + i), data[4*i:4*i+32]
        if command[0] == 'x': chip_erase()
        if command[0] == 'F': program_flash(command[1:].strip())
    return True

def run(devnum = 0):
    global Arduino
    fd = comm.open(devnum=devnum, baud=comm.B500000)
    with contextlib.closing(os.fdopen(fd, "r+b", 1)) as Arduino:
        try:
            while True:
                line = Arduino.readline().rstrip()
                #print "start up line:", repr(line)
                if line == "READY": break
            print "Power up the chip and press ENTER."
            raw_input()
            enable_programming()
            read_configuration()
            while menu(): pass
        finally:
            power_off()
            print "Power off the chip and hit ENTER."
            raw_input()

if __name__ == "__main__":
    run()
