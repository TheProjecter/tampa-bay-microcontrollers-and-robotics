// rotating_platform.pde

// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

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

void
turn_column_off(void) {
  PORTB = PORTC = PORTD = 0;
}

void
set_column(byte b1, byte b2, byte column) {
  turn_column_off();
  byte c = (column << 1) & 0x0E; // column address
  PORTC = c;          // get the demux and transistors started
  byte d = b1 & 0xFE;
  byte b = b2 & 0x3F;
  c |= b1 & 1;
  c |= (b2 >> 2) & 0x30;
  PORTB = b;
  PORTC = c;
  PORTD = d;
  GTCCR = 2;     // reset prescalar for timer2
  TCNT2 = 0;     // set timer2 value to 0
  TIFR2 = 2;     // reset OCF2A flag (match on OCR2A reg)
  TIMSK2 = 0x06; // enable compare match OCR2A and OCR2B interrupt
}

ISR(TIMER2_COMPA_vect) {
  TIMSK2 = 0x04;   // disable compare match OCR2A interrupt,
                   // leave OCR2B match enabled.
  turn_column_off();
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
pulse_row(byte b1, byte b2) {
  for (byte column = 7; column; column -= 1) {
    set_column(b1, b2, column);
    while (TCNT2 < 55) ;
  }
}

void
led_test(void) {
  byte b1, b2, column;
  for (;;) {
    // test columns:
    for (column = 0; column < 8; column++) {
      set_column(0xff, 0xff, column);
      delay(250);
    }

    // test rows:
    b2 = 0;
    for (b1 = 1; b1; b1 <<= 1) {
      pulse_row(b1, b2);
      delay(250);
    }
    for (b2 = 1; b2; b2 <<= 1) {
      pulse_row(b1, b2);
      delay(250);
    }
  }
}

void
comm_test(void) {
  for (;;) {
    byte abort = 0;
    unsigned int errors = 0;
    while (!(UCSR0A & (1 << RXC0))) ;
    unsigned long start_time = millis();
    if (UDR0 != 0) errors += 1;
    for (byte i = 1; i; i++) {
      while (!(UCSR0A & (1 << RXC0))) ;
      if (millis() - start_time > 20) {
        abort = 1;
        break;
      }
      if (UDR0 != i) errors += 1;
    }
    if (!abort) {
      set_column(0xF0 | (errors >> 8), errors, 0);
    }
  }
}

void
setup(void) {
  // turn off pull-ups, set output ports LOW
  PORTB = PORTC = PORTD = 0;

  DDRD = 0xFE;    // 7 output pins, 1 input (RX) (0 in, 1-7 out)
  DDRB = 0x3F;    // 6 output pins (8-13 out)
  DDRC = 0x39;    // 4 output pins, 2 input (0 out, 1-2 in, 3-5 out)
  PORTC = 0x06;   // enable pullups on 1-2

  // set up Timer2 in normal mode with prescaler of 32 (2uSec per timer tick).
  // TCNT2 has timer count.
  // GTCCR = 2 to reset prescaler count
  OCR2A = 50;     // .1mSec (100uSec)
  OCR2B = 75;     // .15mSec (150uSec)
  ASSR = 0;
  TIMSK2 = 0;     // disable interrupts
  TCCR2A = 0x00;  // normal mode
  TCCR2B = 0x03;  // prescaler = 32

  // set up USART for 250K, 8-N-1, no interrupts
  UBRR0H = 0;
  UBRR0L = 3;     // 250K baud
  UCSR0A = 0x00;  // turn off double speed and multi-processor mode
  UCSR0C = 0x06;  // 8-N-1
  UCSR0B = 0x10;  // enable receiver, disable transmitter, disable all intr

  byte c = PINC;  // read push buttons
  PORTC = 0;      // all outputs LOW
  DDRC = 0x3F;    // 6 output pins (0-5 out)

  if (c & 0x02) led_test();
  if (c & 0x04) comm_test();
  Column = 7;
}

void
loop(void) {
  Loop_again = 1;
  while (Loop_again) {
    Loop_again = 0;     // set by OCR2B timer interrupt if .15mSec passes
    while (!(UCSR0A & (1 << RXC0))) ;
    Byte1 = UDR0;
    while (!(UCSR0A & (1 << RXC0))) ;
    Byte2 = UDR0;
  }
  set_column(Byte1, Byte2, Column);
  Column = (Column - 1) & 0x07;
}
