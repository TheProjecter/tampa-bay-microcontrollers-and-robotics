// stationary_platform.pde

// These are grouped on the same port (PIND) so they can be sampled together:
#define SLIDE_SWITCH_PIN        4       /* 0x10 */
#define PUSH_BUTTON_PIN         5       /* 0x20 */
#define MAGNETIC_PICKUP_PIN     7       /* 0x80 */

// The IRDA_TX_PIN is bit 0 of PORTB:
#define IRDA_TX_PIN             8
#define IRDA_SD_PIN             9

// The CTS pin is on its own port so it doesn't get overwritten by other
// writes:
#define CTS_PIN                 14

// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

// Min bytes received in sending buf to start the frame display.
#define MIN_BYTES               100

#define SYNC_CHAR   0xD8
#define ESC_CHAR    0x27

#line 25 "stationary_platform.pde"

void
setup(void) {
  // set up USART for 500K, 8-N-1, no interrupts
  UBRR0H = 0;
  UBRR0L = 1;          // 500K baud
  UCSR0A = 0x00;       // turn off double speed and multi-processor mode
  UCSR0C = 0x06;       // 8-N-1
  UCSR0B = 0x18;       // enable receiver, enable transmitter, disable all intr
  pinMode(0, INPUT);   // USART RX
  pinMode(1, OUTPUT);  // USART TX

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

  // Set up timer1 to tick at 4 uSec/tick.  Max range 262 mSec.
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

  // Set up timer2 to tick at .5 uSec/tick.
  TIMSK2 = 0;     // disable interrupts
  TCCR2A = 0;     // WGM = 0 (normal mode)
  TCCR2B = 0x02;  // prescaler: timer clk == cpu clk / 8
  ASSR = 0;
  // GTCCR = 2 will reset timer2 prescaler
}

unsigned int Rotation;         // ticks/rotation (4 uSec/tick)
unsigned int Slice;            // ticks/slice (4 uSec/tick)

byte Buffer[2][800];
byte Send_buf = 0;           // toggles between 0 and 1
byte Recv_buf = 0;           // toggles between 0 and 1
byte *Recv_start = Buffer[Recv_buf];
byte *Bytep = Recv_start;
byte *Endp = Bytep + 799;    // Set to last byte position to accept data into
byte Ignore_next_escape = 0;
byte Sync_seen = 0;
byte Recv_ok = 1;

#define WAIT_SYNC_START         0
#define WAIT_MIN_START          1
#define SEND                    2
#define WAIT_SEND               3
#define WAIT_MAG                4
#define WAIT_MAG2               5

byte State = WAIT_SYNC_START;

#define RECV_TEST()                         \
  if (Recv_ok && (UCSR0A & (1 << RXC0))) {  \
    byte c = UDR0;                          \
    if (Bytep <= Endp) {                    \
      if (Ignore_next_escape) {             \
        Ignore_next_escape = 0;             \
        *Bytep++ = c;                       \
      } else {                              \
        if (c == SYNC_CHAR) {               \
          PORTC = 1;                        \
          Sync_seen = 1;                    \
          Recv_ok = 0;                      \
        } else if (c == ESC_CHAR) {         \
          Ignore_next_escape = 1;           \
        } else {                            \
          *Bytep++ = c;                     \
        }                                   \
      }                                     \
    } /* end if (Bytep <= Endp) */          \
    if (Bytep >= Endp) {                    \
      PORTC = 1;    /* Stop PC */           \
    }                                       \
  } /* end if (Recv_ok && byte ready) */

// est 7 cpu cycles, excluding RECV_TEST
#define SEND_BIT(n)                     \
  PORTB = bit;                          \
  bit = ~(n | 0xFE);                    \
  n >>= 1;                              \
  PORTB = 0;                            \
  RECV_TEST()

#define CHECK_SYNC_SEEN()                                          \
  if (Sync_seen) {                                                 \
    if (Recv_buf == Send_buf) {                                    \
      Recv_buf ^= 1;                                               \
      Recv_start = Bytep = Buffer[Recv_buf];                       \
      Endp = Bytep + 799;                                          \
      PORTC = 0;                                                   \
      Recv_ok = 1;                                                 \
    } else if (Bytep - Recv_start < MIN_BYTES) {                   \
      Bytep = Recv_start;  /* incomplete results, throw it away */ \
      PORTC = 0;                                                   \
      Recv_ok = 1;                                                 \
    } else {                                                       \
      State = WAIT_SEND;                                           \
    }                                                              \
  }

#define MAG_CHECK(last_statement)                  \
  if (!(PIND & 0x90) && TCNT1 > 5000) {            \
    /* mag & switch closed == sync mode */         \
    GTCCR = 1; /* reset timer0-1 prescaler */      \
    unsigned int rotation = TCNT1;                 \
    TCNT1 = 0;                                     \
    Slice = (rotation + 25u) / 50u;                \
    Rotation = rotation;                           \
    Send_buf ^= 1;                                 \
    if (Recv_buf == Send_buf) {                    \
      if (Bytep - Recv_start < MIN_BYTES) {        \
        State = WAIT_MAG;                          \
      }                                            \
    } else {                                       \
      Recv_buf ^= 1;                               \
      Recv_start = Bytep = Buffer[Recv_buf];       \
      Endp = Bytep + 799;                          \
      if (State == WAIT_SEND) {                    \
        PORTC = 0;                                 \
        Recv_ok = 1;                               \
        State = SEND;                              \
      } else {                                     \
        State = WAIT_SYNC_START;                   \
      }                                            \
    }                                              \
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
  CHECK_SYNC_SEEN();
  MAG_CHECK(return 1);
  bit = 0x01;           // next start bit
  WAIT_UNTIL(10*8);

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
  // Should have about 25 uSec of idle time here...
  CHECK_SYNC_SEEN();
  MAG_CHECK(return 1);
  WAIT_UNTIL(200);      // includes extra wait time for .1 mSec/column
  return 0;
}

byte
send_slice(byte *p) {
  // This function takes .8 mSec to run.
  for (byte i = 0; i < 16; i += 2) {
    if (send_2_bytes(p[i], p[i+1])) return 1;
  }
  return 0;
}

byte
send_frame(byte *p) {
  // This sends one complete revolution (800 bytes).
  // Timer1 (TCNT1) has been zeroed at the start of the revolution.
  // Slice holds the number of Timer1 ticks per slice.
  unsigned int end_time = Slice;
  for (int i = 0; i < 800; i += 16) {
    if (send_slice(p + i)) return 1;
    // There should be at least .2 mSec of idle time here:
    RECV_TEST();
    if (Bytep <= Endp) PORTC = 0;  // enable hardware flow control
    while (TCNT1 < end_time) {
      if (Send_buf == Recv_buf && Bytep > Endp) {
        PORTC = 0;                 // enable hardware flow control
        Recv_buf ^= 1;
        Bytep = Buffer[Recv_buf];
        Endp = Bytep + 799;
      }
      RECV_TEST();
      MAG_CHECK(return 1);
    }
    end_time += Slice;
  }
  return 0;
}

void
send_256(void) {
  for (int i = 0; i < 255; i += 2) {
    send_2_bytes(byte(i), byte(i + 1));
  }
}

void
loop(void) {
  switch (State) {
  case WAIT_SYNC_START:
    if (UCSR0A & (1 << RXC0)) {
      byte c = UDR0;
      if (Ignore_next_escape) Ignore_next_escape = 0;
      else if (c == ESC_CHAR) Ignore_next_escape = 1;
      else if (c == SYNC_CHAR) State = WAIT_MIN_START;
    }
    if (!(PIND & 0x20)) { // push button down
      send_256();
      TCNT1 = 0;
      while (TCNT1 < 62500u) ;    // delay 250 mSec
      TCNT1 = 0;
      while (TCNT1 < 62500u) ;    // delay 250 mSec
    }
    break;
  case WAIT_MIN_START:
    if (UCSR0A & (1 << RXC0)) {
      byte c = UDR0;
      if (Ignore_next_escape) {
        Ignore_next_escape = 0;
        if (Bytep <= Endp) *Bytep++ = c;
      } else if (c == ESC_CHAR) Ignore_next_escape = 1;
      else if (c == SYNC_CHAR) {
        if (Bytep - Recv_start < MIN_BYTES) {
          Bytep = Recv_start;  // incomplete, throw away data
        } else if (Recv_buf == Send_buf) {
          Recv_buf ^= 1;
          Bytep = Recv_start = Buffer[Recv_buf];
        } else {
          PORTC = 1;
          Recv_ok = 0;
          State = WAIT_SEND;
        }
      } else if (Bytep <= Endp) *Bytep++ = c;
    }
    if ((!(PIND & 0x80) || (PIND & 0x10)) && TCNT1 > 5000) {
      // mag || switch open == async mode
      GTCCR = 1; // reset timer0-1 prescaler
      unsigned int rotation = TCNT1;
      TCNT1 = 0;
      Slice = (rotation + 25u) / 50u;
      Rotation = rotation;
      State = SEND;
    }
    break;
  case SEND:
  case WAIT_SEND:
    send_frame(Buffer[Send_buf]);
    break;
  case WAIT_MAG:
    if (UCSR0A & (1 << RXC0)) {
      byte c = UDR0;
      if (Ignore_next_escape) {
        Ignore_next_escape = 0;
        if (Bytep <= Endp) *Bytep++ = c;
      } else if (c == ESC_CHAR) Ignore_next_escape = 1;
      else if (c == SYNC_CHAR) {
        if (Bytep - Recv_start < MIN_BYTES) {
          Bytep = Recv_start;  // incomplete, throw data away
        } else if (Recv_buf == Send_buf) {
          Recv_buf ^= 1;
          Bytep = Recv_start = Buffer[Recv_buf];
          Endp = Bytep + 799;
        } else {
          PORTC = 1;
          Recv_ok = 0;
          State = WAIT_MAG2;
        }
      } else if (Bytep <= Endp) *Bytep++ = c;
    }
    if ((!(PIND & 0x80) || (PIND & 0x10)) && TCNT1 > 5000 && 
        Bytep - Recv_start > MIN_BYTES
    ) {
      State = SEND;
    }
    break;
  case WAIT_MAG2:
    if ((!(PIND & 0x80) || (PIND & 0x10)) && TCNT1 > 5000) {
      PORTC = 0;
      Recv_ok = 1;
      State = SEND;
    }
    break;
  } // end switch (State)
}
