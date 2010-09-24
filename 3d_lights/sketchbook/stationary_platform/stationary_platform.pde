// stationary_platform.pde

// These are grouped on the same port (PORTD) so they can be sampled together:
#define SLIDE_SWITCH_PIN        4
#define PUSH_BUTTON_PIN         5
#define MAGNETIC_PICKUP_PIN     7

// The IRDA_TX_PIN is bit 0 of PORTB:
#define IRDA_TX_PIN             8
#define IRDA_SD_PIN             9

// The CTS pin is on its own port so it doesn't get overwritten by other
// writes:
#define CTS_PIN                 14

// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

unsigned int Rotation;         // ticks/rotation (4 uSec/tick)
unsigned int Slice;            // ticks/slice (4 uSec/tick)

#line 23 "stationary_platform.pde"

void
help(void) {
  Serial.println("h  -- help");
}

void
setup(void) {
  // set up USART for 500K, 8-N-1, no interrupts
  UBRR0H = 0;
  UBRR0L = 1;     // 500K baud
  UCSR0A = 0x00;  // turn off double speed and multi-processor mode
  UCSR0C = 0x06;  // 8-N-1
  UCSR0B = 0x18;  // enable receiver, enable transmitter, disable all intr

  // Set up IrDA:
  pinMode(IRDA_TX_PIN, OUTPUT);     // IrDA TX
  pinMode(IRDA_SD_PIN, OUTPUT);     // IrDA SD
  digitalWrite(IRDA_TX_PIN, LOW);   // default LOW

  // Set IrDA to high-speed mode:
  digitalWrite(IRDA_SD_PIN, HIGH);  // SD
  digitalWrite(IRDA_TX_PIN, HIGH);  // TX
  delayMicroseconds(2);
  digitalWrite(IRDA_SD_PIN, LOW);  // SD
  delayMicroseconds(2);
  digitalWrite(IRDA_TX_PIN, LOW);  // TX

  // Set up input pins:
  pinMode(SLIDE_SWITCH_PIN, INPUT);         // slide switch
  digitalWrite(SLIDE_SWITCH_PIN, HIGH);     // enable pull-up resistor
  pinMode(PUSH_BUTTON_PIN, INPUT);          // push button
  digitalWrite(PUSH_BUTTON_PIN, HIGH);      // enable pull-up resistor
  pinMode(MAGNETIC_PICKUP_PIN, INPUT);      // magnetic pickup
  digitalWrite(MAGNETIC_PICKUP_PIN, HIGH);  // enable pull-up resistor

  // Set up CTS pin:
  pinMode(CTS_PIN, OUTPUT);
  digitalWrite(CTS_PIN, LOW);               // enable PC to send data

  TIMSK0 = 0;     // disable interrupts: micros, millis and delay don't work
                  //                     from here on...

  // Set up timer 1 to tick at 4 uSec/tick.  Max range 262 mSec.
  //
  // The plan is to reset the counter at the start of each revolution.  This
  // will only work if the rps is > 4.
  //
  // Then divide that by 50 to get the time between slices.
  //
  // Then do 25 ticks (100 uSec) per column, 10 ticks/byte transmitted, 1
  // tick/bit.
  TIMSK1 = 0;     // disable interrupts
  TCCR1A = 0;     // WGM = 0 (normal mode)
  TCCR1B = 0x03;  // prescaler: timer clk == cpu clk / 64
  // GTCCR = 1 will reset timer0-1 prescaler

  // Set up timer 2 to tick at .5 uSec/tick.
  TIMSK2 = 0;     // disable interrupts
  TCCR2A = 0;     // WGM = 0 (normal mode)
  TCCR2B = 0x02;  // prescaler: timer clk == cpu clk / 8
  ASSR = 0;
  // GTCCR = 2 will reset timer2 prescaler

  help();
}

byte Buffer[2][800];
byte Recv_buf = 0;
byte *Bytep = Buffer[Recv_buf];
byte *Endp = Bytep + 799;    // Set to last byte position to accept data into
byte Start_frame = 0;        // True to start displaying the next rotation

#define RECV_TEST()                     \
  if (UCSR0A & (1 << RXC0)) {           \
    if (Bytep <= Endp) {                \
      *Bytep++ = UDR0;                  \
    }                                   \
    if (Bytep >= Endp) {                \
      PORTC = 0x01; /* Stop PC */       \
    }                                   \
  }

// est 7 cpu cycles, excluding RECV_TEST
#define SEND_BIT(n)                     \
  PORTB = bit;                          \
  bit = ~(n | 0xFE);                    \
  n >>= 1;                              \
  PORTB = 0;                            \
  RECV_TEST()

#define MAG_CHECK(last_statement)                  \
  if (!(PIND & 0x90)) { /* mag & switch closed */  \
    GTCCR = 1; /* reset timer0-1 prescaler */      \
    unsigned int rotation = TCNT1;                 \
    TCNT1 = 0;                                     \
    Slice = (rotation + 25u) / 50u;                \
    Rotation = rotation;                           \
    Start_frame = 1;                               \
    last_statement;                                \
  }

#define WAIT_UNTIL(time)                \
  while (TCNT2 < (time)) 

byte
send_2_bytes(byte n1, byte n2) {
  // This takes .1 mSec to execute, or the time for 1 column.
  byte bit = 0x01;
  GTCCR = 2;            // reset timer2 prescalar
  TCNT2 = 0;            // reset timer2 counter

  SEND_BIT(n1);         // start bit
  WAIT_UNTIL(8+1);
  SEND_BIT(n1);         // bit 0
  WAIT_UNTIL(2*8+1);
  SEND_BIT(n1);         // bit 1
  WAIT_UNTIL(3*8+1);
  SEND_BIT(n1);         // bit 2
  WAIT_UNTIL(4*8+1);
  SEND_BIT(n1);         // bit 3
  WAIT_UNTIL(5*8+1);
  SEND_BIT(n1);         // bit 4
  WAIT_UNTIL(6*8+1);
  SEND_BIT(n1);         // bit 5
  WAIT_UNTIL(7*8+1);
  SEND_BIT(n1);         // bit 6
  WAIT_UNTIL(8*8+1);
  SEND_BIT(n1);         // bit 7 + stop bit
  MAG_CHECK(return 1);
  WAIT_UNTIL(10*8);

  bit = 0x01;
  SEND_BIT(n2);         // start bit
  WAIT_UNTIL(11*8+1);
  SEND_BIT(n2);         // bit 0
  WAIT_UNTIL(12*8+1);
  SEND_BIT(n2);         // bit 1
  WAIT_UNTIL(13*8+1);
  SEND_BIT(n2);         // bit 2
  WAIT_UNTIL(14*8+1);
  SEND_BIT(n2);         // bit 3
  WAIT_UNTIL(15*8+1);
  SEND_BIT(n2);         // bit 4
  WAIT_UNTIL(16*8+1);
  SEND_BIT(n2);         // bit 5
  WAIT_UNTIL(17*8+1);
  SEND_BIT(n2);         // bit 6
  WAIT_UNTIL(18*8+1);
  SEND_BIT(n2);         // bit 7 + stop bit
  MAG_CHECK(return 1);
  WAIT_UNTIL(200);      // includes extra wait time for .1 mSec/column
  return 0;
}

byte
send_slice(byte *p) {
  for (byte i = 0; i < 16; i += 2) {
    if (send_2_bytes(p[i], p[i+1])) return 1;
  }
  // delay .2 mSec (sync pause at end of slice)
  unsigned int end_time = TCNT1 + 50;
  while (TCNT1 < end_time) {
    // There may be up to 2 bytes left to recv.
    if ((PORTC & 1) && Bytep <= Endp) PORTC = 0;
    RECV_TEST();
    MAG_CHECK(return 1);
  }
  return 0;
}

void
send_frame(byte *p) {
  unsigned int end_time = Slice;
  for (int i = 0; i < 800; i += 16) {
    if (send_slice(p + i)) break;
    while (TCNT1 < end_time) {
      if ((PORTC & 1) && Bytep <= Endp) {
        PORTC = 0;    // enable hardware flow control
      }
      RECV_TEST();
      MAG_CHECK();
    }
    end_time += Slice;
  }
}

void
send_256(void) {
  Serial.println("Sending all 256 chars");
  for (int i = 0; i < 255; i += 2) {
    send_2_bytes(byte(i), byte(i + 1));
  }
  Serial.println("sent");
}

void
loop(void) {
  if (Bytep >= Endp) {
    if (PIND & 0x10) {  // switch open == async mode
      Start_frame = 1;
      GTCCR = 1; // reset timer0-1 prescaler
      TCNT1 = 0;
      Slice = 250;
    }
    if (Start_frame) {
      byte *p = Buffer[Recv_buf];
      Recv_buf ^= 1;
      Bytep = Buffer[Recv_buf];
      Endp = Bytep + 799;
      PORTC = 0;     // enable hardware flow control
      Start_frame = 0;
      send_frame(p);
    } else MAG_CHECK()
  } else {
    PORTC = 0;     // enable hardware flow control
    RECV_TEST()
    else MAG_CHECK()
    else if (!digitalRead(PUSH_BUTTON_PIN)) {
      send_256();
      TCNT1 = 0;
      while (TCNT1 < 62500u) ;    // delay 250 mSec
      TCNT1 = 0;
      while (TCNT1 < 62500u) ;    // delay 250 mSec
    }
  }
}
