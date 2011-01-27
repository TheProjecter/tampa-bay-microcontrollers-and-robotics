// serial_programmer.pde

#include <ctype.h>
#include <avr/io.h>
#include <avr/pgmspace.h>

#include <SPI.h>

// SPI bus uses pins 10 (SS), 11 (MOSI), 12 (MISO), and 13 (SCK)

const prog_char Help_msg1[] PROGMEM =
    "h          - print this help message\n";
const prog_char Help_msg2[] PROGMEM =
    "r xx       - read I/O reg xx (hex) (larger I/O number)\n";
const prog_char Help_msg3[] PROGMEM =
    "w xx=yy    - write yy to I/O reg xx (both hex)\n";
const prog_char Help_msg4[] PROGMEM =
    "s wwxxyyzz - send 4 bytes (hex) to SPI\n";
const prog_char Help_msg5[] PROGMEM =
    "d dd       - delay dd mSec\n";

const prog_char Input_buf_overflow[] PROGMEM =
    "ERROR: Input buffer overflow, command too long\n";

const prog_char Illegal_hex[] PROGMEM =
    "ERROR: Illegal hex char, ";

const prog_char Illegal_decimal[] PROGMEM =
    "ERROR: Illegal decimal char, ";

const prog_char Argument_too_long[] PROGMEM =
    "ERROR: Argument too long.\n";

const prog_char Read_msg1[] PROGMEM =
    "Read from 0x";
const prog_char Missing_equal[] PROGMEM =
    "ERROR: Missing '=' in write command.\n";

const prog_char Wrote_msg1[] PROGMEM =
    "Wrote 0x";
const prog_char Wrote_msg2[] PROGMEM =
    " to register 0x";

const prog_char Send_msg1[] PROGMEM =
    "Send got 0x";
const prog_char Delayed_msg1[] PROGMEM =
    "Delayed ";
const prog_char Delayed_msg2[] PROGMEM =
    "mSec.\n";
const prog_char Unknown_command[] PROGMEM =
    "ERROR: Unknown command.\n";

const prog_char Missing_argument[] PROGMEM =
    "ERROR: Missing argument.\n";


#define BUFFER_SIZE     70

char Buffer[BUFFER_SIZE];

void
print_P(const prog_char *str) {
    strcpy_P(Buffer, str);
    Serial.print(Buffer);
}

void
print_hex(byte n, byte newline = 0) {
    if (n < 16) Serial.print('0', BYTE);
    Serial.print(n, HEX);
    if (newline) Serial.print('\n', BYTE);
}

byte
hex(char c) {
    if ('0' <= c && c <= '9') return c - '0';
    if ('a' <= c && c <= 'f') return c - 'a' + 10;
    print_P(Illegal_hex);
    Serial.print(c, BYTE);
    Serial.print('\n', BYTE);
    return 255;
}

int
read_hex(const char *arg) {
    byte h1 = hex(arg[0]);
    byte h2 = hex(arg[1]);
    if (h1 == 255 || h2 == 255) return -1;
    return (h1 << 4) | h2;
}

byte
decimal(char c) {
    if ('0' <= c && c <= '9') return c - '0';
    print_P(Illegal_decimal);
    Serial.print(c, BYTE);
    Serial.print('\n', BYTE);
    return 255;
}

int
read_dec(const char *arg) {
    int ans = 0;
    byte i;
    for (i = 0; arg[i]; i++) {
        byte d = decimal(arg[i]);
        if (d == 255) return -1;
        ans = 10*ans + d;
    } // end for (i)
    if (i == 0) print_P(Missing_argument);
    return ans;
}

const char *
get_command(void) {
    for (;;) {
        for (byte i = 0; i < BUFFER_SIZE; i++) {
            while (Serial.available() == 0) ;
            byte c = Serial.read();
            if (c == '\n' || c == '\r') {
                Buffer[i] = 0;
                return Buffer;
            }
            if (c == ' ' || c == '\t') i--;
            else Buffer[i] = tolower(c);
        } // end for (i)
        print_P(Input_buf_overflow);
    } // end for (;;)
}

void
help(void) {
    print_P(Help_msg1);
    print_P(Help_msg2);
    print_P(Help_msg3);
    print_P(Help_msg4);
    print_P(Help_msg5);
}

void
setup(void) {
    Serial.begin(57600);
    //Serial.begin(500000);

    SPI.setBitOrder(MSBFIRST);
    SPI.setDataMode(SPI_MODE0);
    SPI.setClockDivider(SPI_CLOCK_DIV128);

    help();

    pinMode(9, OUTPUT);
    digitalWrite(9, LOW);
}

void
read(const char *arg) {
    int addr = read_hex(arg);
    if (addr < 0) return;
    if (arg[2]) {
        print_P(Argument_too_long);
        return;
    }
    print_P(Read_msg1);
    print_hex(addr);
    Serial.print(": 0x");
    print_hex(*((byte *)addr), 1);
}

void
write(const char *arg) {
    int addr = read_hex(arg);
    if (addr < 0) return;
    if (arg[2] != '=') {
        print_P(Missing_equal);
        return;
    }
    int data = read_hex(arg + 3);
    if (data < 0) return;
    if (arg[5]) {
        print_P(Argument_too_long);
        return;
    }
    *((byte *)addr) = byte(data);
    print_P(Wrote_msg1);
    print_hex(data);
    print_P(Wrote_msg2);
    print_hex(byte(addr), 1);
}

void
send(const char *arg) {
    byte data_out[4];
    byte data_in[4];
    byte i;
    for (i = 0; i < 4; i++) {
        int data1 = read_hex(arg + 2*i);
        if (data1 < 0) return;
        data_out[i] = byte(data1);
    } // end for (i)
    if (arg[8]) {
        print_P(Argument_too_long);
        return;
    }
    SPI.begin();
    data_in[0] = SPI.transfer(data_out[0]);
    data_in[1] = SPI.transfer(data_out[1]);
    data_in[2] = SPI.transfer(data_out[2]);
    data_in[3] = SPI.transfer(data_out[3]);
    SPI.end();
    print_P(Send_msg1);
    for (i = 0; i < 4; i++) {
        print_hex(data_in[i]);
    } // end for (i)
    Serial.print('\n', BYTE);
}

void
do_delay(const char *arg) {
    int msec = read_dec(arg);
    if (msec < 0) return;
    delay(msec);
    print_P(Delayed_msg1);
    Serial.print(msec, DEC);
    print_P(Delayed_msg2);
}

void
loop(void) {
    const char *command = get_command();
    switch (command[0]) {
    case 0: break;  // user just hit newline
    case 'h': help(); break;
    case 'r': read(command + 1); break;
    case 'w': write(command + 1); break;
    case 's': send(command + 1); break;
    case 'd': do_delay(command + 1); break;
    default: print_P(Unknown_command); break;
    } // end switch (command[0])
}
