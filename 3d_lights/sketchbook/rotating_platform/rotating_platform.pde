// rotating_platform.pde

// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

/********************************************************
Pin assignments:

  16 LED columns (least to most significant, using Arduino pin #s):
    analog pins 0-1
    pins 2-12
    analog pins 3-5
  
  3 LED row address bits (least to most significant):
    pin 1 (labeled TX on Arduino), also serves as LED TEST button (on LOW)
    analog pin 2, also serves as COMM TEST button (on LOW)
    pin 13
  
  IrDA RX line:
    pin 0 (labeled RX on Arduino)

*********************************************************/

/********************************************************
 This program does not use the Arduino timer functions (micros, millis or
 delay).  So it _could_ use timer0 for the normal processing (which uses less
 current), I just haven't made the effort yet to figure out how timer0 works
 and make the switch...
*********************************************************/

/********************************************************

USART registers:

UDR0    - data register: send/recv data here
UCSR0A  - status register (MSB to LSB):
             RXC0  - set when recv complete
             TXC0  - set when transmit complete (may trigger Trans Compl int)
             UDRE0 - set when data reg ready (for next transmitted byte)
             FE0   - set if framing error
             DOR0  - set if data overrun
             UPE0  - set if parity error
             U2X0  - set for double transmission speed
             MPCM0 - set for multi-processor mode
UCSR0B  - 
             RXCIE0 - set to enable intr on RXC0 flag
             TXCIE0 - set to enable intr on TXC0 flag
             UDRIE0 - set to enable intr on UDRE0 flag
             RXEN0  - set to enable the receiver
             TXEN0  - set to enable the transmitter
             UCSZ02 - char size
             RXB80  - ninth received data bit
             TXB80  - ninth data bit to transmit

UCSR0C  -
             UMSEL01
             UMSEL00 - 00 async, 01 sync, 10 resv, 11 master SPI
             UPM01
             UPM00   - 00 no parity, 01 resv, 10 even parity, 11 odd parity
             USBS0   - 0=1 stop bit, 1=2 stop bits
             UCSZ01    (UCSZ02 in UCSR0B register)
             UCSZ00  - 000 5 bits, 001 6, 010 7, 011 8, 100 & 101 resv, 111 9
             UCPOL0  - 0 for async

UBRR0H  - (only last 4 bits used)
UBRR0L  - baud rate register, 1=500K, 3=250K

*********************************************************/

#define TURN_COLUMN_OFF()       \
  PORTB = 0;                    \
  PORTC = 0;                    \
  PORTD = 0

void
set_column(byte b1, byte b2, byte column) {
  TURN_COLUMN_OFF();
  column <<= 1;
  byte d = (b1 & 0xFC) | (column & 0x02);
  byte b = ((column << 2) & 0x20) | (b2 & 0x1F);
  byte c = ((b2 >> 2) & 0x38) | (column & 0x04) | (b1 & 0x03);
  PORTB = b;
  PORTC = c;
  PORTD = d;
  GTCCR = 2;     // reset prescalar for timer2
  TCNT2 = 255;   // set timer2 value to 0xFF
  TIFR2 = 6;     // reset OCF2A (2) and OCF2B (4) match flags
  TIMSK2 = 0x06; // enable compare match OCR2A and OCR2B interrupt
}

ISR(TIMER2_COMPA_vect) {
  TIMSK2 = 0x04;   // disable compare match OCR2A interrupt,
                   // leave OCR2B match enabled.
  TURN_COLUMN_OFF();
}

byte Column;
byte Loop_again;
byte Byte1, Byte2;

ISR(TIMER2_COMPB_vect) {
  TIMSK2 = 0;     // disable compare match OCR2A and OCR2B interrupt
  Column = 7;
  Loop_again = 1;
}

void
wait_until(byte stop_time) {
  while (TCNT2 >= 250) ;         // wait for timer to roll over
  while (TCNT2 < stop_time) ;    // wait for stop_time
}

void
wait_millis(int millis) {
  for (int i = 0; i < millis; i++) {
    wait_until(250);
    wait_until(250);
  }
}

void
pulse_row(byte b1, byte b2) {
  for (byte column = 8; column;) {
    set_column(b1, b2, --column);
    wait_until(55);         // wait long enough for intr to turn them off
  }
}

void
led_test(void) {
  byte column;
  // test columns:
  for (column = 8; column;) {
    set_column(0xff, 0xff, --column);
    wait_millis(250);
  }

  // test rows:
  byte b1, b2 = 0;
  for (b1 = 1; b1; b1 <<= 1) {
    pulse_row(b1, b2);
    wait_millis(250);
  }
  for (b2 = 1; b2; b2 <<= 1) {
    pulse_row(b1, b2);
    wait_millis(250);
  }
}

void
comm_test(void) {
  unsigned int errors = 0;
  while (!(UCSR0A & (1 << RXC0))) ;
  if (UDR0 != 0) errors += 1;
  for (byte i = 1; i; i++) {
    TCNT2 = 0;
    while (!(UCSR0A & (1 << RXC0))) {
      if (TCNT2 > 200) return;    // don't wait longer than 400 uSec
    }
    if (UDR0 != i) errors += 1;
  }
  set_column(byte(errors), 0xF0 | byte(errors >> 8), 7);
  wait_until(53); // wait for lights to turn off before reseting TCNT2 again...
}

unsigned int Framing_errors[2] = {0, 0};
unsigned int Overrun_errors = 0;
unsigned int Wrong_data_errors = 0;
unsigned int Min_time_errors[2] = {0, 0};
unsigned int Max_time_errors[2] = {0, 0};

void
report_int(unsigned int n, byte column) {
  set_column(byte(n), 0xC0 | byte(n >> 8), column);
  wait_until(53); // wait for lights to turn off before reseting TCNT2 again...
}

void
report_comm2_test(void) {
  // display until reset...
  for (;;) {
    // each report_int resets TCNT2 to 255
    report_int(Framing_errors[0],  7);
    report_int(Framing_errors[1],  6);
    report_int(Overrun_errors,     5);
    report_int(Min_time_errors[0], 4);
    report_int(Min_time_errors[1], 3);
    report_int(Max_time_errors[0], 2);
    report_int(Max_time_errors[1], 1);
    report_int(Wrong_data_errors,  0);
    wait_until(129); // 1mSec from start of report == TCNT2 of 500
                     // 500 - 53 * 7 == 129
  } // end for (;;)
}

void
check_byte(byte expected, byte index, byte max_time) {
  byte flags;
  if (max_time < 200) max_time = 200;
  while (!(flags = (UCSR0A & ((1 << RXC0) | (1 << FE0) | (1 << DOR0))))) {
    if (TCNT2 > max_time) return;
  }
  if (flags & (1 << FE0)) Framing_errors[index] += 1;
  if (flags & (1 << DOR0)) Overrun_errors += 1;
  if (UDR0 != expected) Wrong_data_errors += 1;
}

byte
check_byte_timed(byte expected, byte index,
                 byte min_time, byte max_time, byte time_index
) {
  check_byte(expected, index, max_time);
  byte time = TCNT2;
  if (time < min_time) Min_time_errors[time_index] += 1;
  if (time > max_time) Max_time_errors[time_index] += 1;
  return time;
}

byte
comm2_test_slice(byte first, byte skip_first) {
  // wait for the show to start...
  if (!skip_first) {
    if (first) check_byte_timed(0x01, 0, 0, 255, 0);      // 0-inf
    else       check_byte_timed(0x01, 0, 112, 138, 0);    // 896-1104 uSec
  }
  GTCCR = 2;     // reset prescalar for timer2
  TCNT2 = 0;     // timer2 ticks at 8uSec/tick
  byte time1 = 0;
  byte time2 = check_byte_timed(0x80, 1, 0, time1 + 6, 1);
  if (time2 > time1 + 23) return 1;
  for (byte i = 1; i < 8; i++) {
    // 96-120 uSec from last column
    time1 = check_byte_timed(0x01 << i, 0, time1 + 12, time1 + 15, 0);
    if (time1 > time2 + 90) return 1;
    // 0-48 uSec from start of column
    time2 = check_byte_timed(0x80 >> i, 1, 0, time1 + 6, 1);
    if (time2 > time1 + 90) return 1;
  } // end for (i)
  return 0;
}

void
comm2_test(void) {
  byte first = 1;
  byte skip_first = 0;
  TCCR2B = 0x05;  // prescaler = 128 (8 uSec/tick)
  // wait for the show to start...
  for (byte frame = 0; frame < 3; frame++) {
    for (byte slice = 0; slice < 50; slice++) {
      skip_first = comm2_test_slice(first, skip_first);
      first = 0;
    }
  }
  report_comm2_test();
}

void
setup(void) {
  // turn off pull-ups, set output ports LOW
  PORTB = PORTC = PORTD = 0;

  DDRD = 0xFC;    // 6 output pins, 2 input (RX) (0-1 in, 2-7 out)
  DDRB = 0x3F;    // 6 output pins (8-13 out)
  DDRC = 0x3B;    // 5 output pins, 1 input (0-1 out, 2 in, 3-5 out)
  PORTD = 0x02;   // enable pullup on pin 1
  PORTC = 0x04;   // enable pullup on analog pin 2

  TIMSK0 = 0;     // disable interrupts for timer0 (used by Arduino library
                  // for delay, millis and micros).

  // set up Timer2 in normal mode with prescaler of 32 (2uSec per timer tick).
  // TCNT2 has timer count.
  // GTCCR = 2 to reset prescaler count
  OCR2A = 48;     // .1mSec (100uSec)
                  // (50 - 1 delay - 1 for TCNT2 starting at 0xFF rather than 0)
  OCR2B = 88;     // .18mSec (180uSec)
                  // (90 - 1 delay - 1 for TCNT2 starting at 0xFF rather than 0)
  ASSR = 0;
  TIMSK2 = 0;     // disable interrupts
  TCCR2A = 0x03;  // fast PWM mode
  TCCR2B = 0x03;  // prescaler = 32

  // set up USART for 250K, 8-N-1, no interrupts
  UBRR0H = 0;
  UBRR0L = 3;     // 250K baud
  UCSR0A = 0x00;  // turn off double speed and multi-processor mode
  UCSR0C = 0x06;  // 8-N-1
  UCSR0B = 0x10;  // enable receiver, disable transmitter, disable all intr

  byte led_button = PIND & 0x02;  // read LED push button (on LOW)
  byte comm_button = PINC & 0x04; // read COMM push button (on LOW)
  PORTD = 0;      // all outputs LOW
  DDRD = 0xFE;    // 7 output pins, 1 input (1-7 out, 0 in)
  PORTC = 0;      // all outputs LOW
  DDRC = 0x3F;    // 6 output pins (0-5 out)

  if (!comm_button) {
    // this branch never finishes
    if (led_button) {
      for (;;) comm_test();
    } else comm2_test();  // never returns
  }
  if (!led_button) for (;;) led_test();
  Column = 7;
  interrupts();
}

void
loop(void) {
  // Get first byte for column:
  while (!(UCSR0A & (1 << RXC0))) ;
  Byte1 = UDR0;

  // Get second byte for column:
  for (;;) {   // This should only ever loop once or twice.  After the second
               // loop, Loop_again would not be set again because the
               // interrupts are disabled.
    Loop_again = 0;     // set by OCR2B timer interrupt if .15mSec passes
    while (!(UCSR0A & (1 << RXC0))) ;
    if (Loop_again) {
      // The 180uSec timer fired!  This is our clue to resync to Column 7.
      // This byte is the first byte after the pause and should really be the
      // first byte of Column 7.  (The timer interrupt sets the Column to 7).
      Byte1 = UDR0;
      // loop around again to get Byte2...
    } else {
      // No pause between these two bytes, so we have the second byte for the
      // column now:
      Byte2 = UDR0;
      break;
    }
  }

  // Turn the Byte1/Byte2 LEDs on for the Column.  This resets the timers too.
  set_column(Byte1, Byte2, Column);

  // Decrement Column for the next Column.  This will get overwritten to 7 by
  // the 180uSec timer firing, so that in any case, the Column is set right
  // for the next set of bytes.
  Column = (Column - 1) & 0x07;
}
