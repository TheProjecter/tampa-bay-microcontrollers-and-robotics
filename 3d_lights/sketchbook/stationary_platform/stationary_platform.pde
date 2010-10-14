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
#include <avr/pgmspace.h>

// Min bytes received in sending buf to start the frame display.
#define MIN_BYTES               100

#define SYNC_CHAR   0xD8
#define ESC_CHAR    0x27

#define WELCOME_MSG         1   /* byte test, int test */

// Incomplete_bufs (u1), Where_incomplete (u1),
// Framing_errors (u1), Where_framing_error (u1),
// Data_overrun_errors (u1), Where_data_overrun (u1),
// Buf_overflows (u2), Where_overflow (u1)
#define ERROR_COUNT_MSG     2

#define RPS_MSG             3   /* TCNT1 */

void
print_char(char c) {
  while (!(UCSR0A & (1 << UDRE0))) ;
  UDR0 = c;
}

// use print_P(PSTR("hi mom"))
void
print_P(const char PROGMEM *s, byte newline = 1) {
  for (byte b = pgm_read_byte(s++); b; b = pgm_read_byte(s++)) {
    print_char(b);
  }
  if (newline) {
    print_char('\n');
  }
}

void
print_dec(int n, byte newline = 1) {
  byte printing = 0;
  div_t quot_rem;
  quot_rem.rem = n;
  for (int divisor = 10000; divisor; divisor /= 10) {
    quot_rem = div(quot_rem.rem, divisor);
    if (printing || quot_rem.quot) {
      print_char(quot_rem.quot + '0');
      printing = 1;
    }
  }
  if (!printing) print_char('0');
  if (newline) print_char('\n');
}

void
print_int(int i) {
    byte *bp = (byte *)&i;
    print_char(bp[1]);
    print_char(bp[0]);
}

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

  noInterrupts();
  print_char(WELCOME_MSG);
  print_char(0x12);
  print_int(0x1234);
}

unsigned int Rotation;         // timer1 ticks/rotation (4 uSec/tick)
unsigned int Slice;            // timer1 ticks/slice (4 uSec/tick)

byte Buffer[2][800];
byte Send_buf = 0;           // toggles between 0 and 1
byte Recv_buf = 0;           // toggles between 0 and 1
byte *Recv_start = Buffer[Recv_buf];
byte *Bytep = Recv_start;
byte *Endp = Bytep + 799;    // Set to last byte position to accept data into
byte Ignore_next_escape = 0;
byte Sync_seen = 0;
byte Recv_ok = 1;
byte Read_ahead_buf[2];
byte Read_ahead_count = 0;

#define WAIT_SYNC_START         0
#define WAIT_MIN_BYTES          1
#define WAIT_MAG                2
#define WAIT_MAG2               3
#define SEND                    4

byte State = WAIT_SYNC_START;

#define WHERE_CHECK_SYNC_SEEN1     1
#define WHERE_CHECK_SYNC_SEEN2     2
#define WHERE_WAIT_MIN_BYTES       3
#define WHERE_WAIT_MAG1            4
#define WHERE_WAIT_MAG2            5
#define WHERE_SEND                 6
#define WHERE_RECV_TEST1           7
#define WHERE_RECV_TEST2           8
#define WHERE_WAIT_MAG             9
#define WHERE_WAIT_SYNC_START      10

byte Where_incomplete;
byte Where_overflow;
byte Where_framing_error;
byte Where_data_overrun;
byte Incomplete_bufs;
byte Framing_errors;
byte Data_overrun_errors;
unsigned int Buf_overflows;

void
print_errors(void) {
  PORTC = 1;
  print_char(ERROR_COUNT_MSG);
  print_char(Incomplete_bufs);
  print_char(Where_incomplete);
  print_char(Framing_errors);
  print_char(Where_framing_error);
  print_char(Data_overrun_errors);
  print_char(Where_data_overrun);
  print_int(Buf_overflows);
  print_char(Where_overflow);
  Incomplete_bufs = 0;
  Where_incomplete = 0;
  Framing_errors = 0;
  Where_framing_error = 0;
  Data_overrun_errors = 0;
  Where_data_overrun = 0;
  Buf_overflows = 0;
  Where_overflow = 0;
  if (!Sync_seen) PORTC = 0;
}

byte Rev_count = 0;

void
print_rps(unsigned int rotation) {
  if (++Rev_count >= 10) {
    PORTC = 1;
    print_char(RPS_MSG);
    print_int(rotation);
    Rev_count = 0;
    if (!Sync_seen) PORTC = 0;
  }
}

// Called from:
//   * SEND_BIT (send_2_bytes)
//   * send_frame
#define RECV_TEST(flags)                      \
  if (Recv_ok && (flags = (UCSR0A & ((1 << RXC0) | (1 << FE0) | (1 << DOR0))))) {    \
    byte c = UDR0;                            \
    if (flags & (1 << FE0)) {                 \
      Framing_errors += 1;                    \
      Where_framing_error = WHERE_RECV_TEST1; \
    }                                         \
    if (flags & (1 << DOR0)) {                \
      Data_overrun_errors += 1;               \
      Where_data_overrun = WHERE_RECV_TEST1;  \
    }                                         \
    if (Ignore_next_escape) {                 \
      Ignore_next_escape = 0;                 \
      if (Bytep <= Endp) *Bytep++ = c;        \
      else {                                  \
        Buf_overflows += 1;                   \
        Where_overflow = WHERE_RECV_TEST1;    \
      }                                       \
    } else {                                  \
      if (c == SYNC_CHAR) {                   \
        PORTC = 1;                            \
        Recv_ok = 0;                          \
        Sync_seen = 1;                        \
      } else if (c == ESC_CHAR) {             \
        Ignore_next_escape = 1;               \
      } else {                                \
        if (Bytep <= Endp) *Bytep++ = c;      \
        else {                                \
          Buf_overflows += 1;                 \
          Where_overflow = WHERE_RECV_TEST2;  \
        }                                     \
      }                                       \
    } /* end else if (Ignore_next_escape) */  \
  } /* end if (Recv_ok && byte ready) */

// est 7 cpu cycles, excluding RECV_TEST
// Called from:
//   * send_2_bytes
#define SEND_BIT(n)                     \
  PORTB = bit;                          \
  bit = ~(n | 0xFE);                    \
  n >>= 1;                              \
  PORTB = 0;                            \
  RECV_TEST(flags)

// Called from:
//   * send_2_bytes
//   * send_frame
#define CHECK_SYNC_SEEN(flags)                                     \
  if (Sync_seen) {                                                 \
    /* PORTC == 1 && Recv_ok == 0 */                               \
    if (flags = (UCSR0A & ((1 << RXC0) | (1 << FE0) | (1 << DOR0)))) {  \
      byte c = UDR0;                                               \
      if (flags & (1 << FE0)) {                                    \
        Framing_errors += 1;                                       \
        Where_framing_error = WHERE_CHECK_SYNC_SEEN1;              \
      }                                                            \
      if (flags & (1 << DOR0)) {                                   \
        Data_overrun_errors += 1;                                  \
        Where_data_overrun = WHERE_CHECK_SYNC_SEEN1;               \
      }                                                            \
      if (Read_ahead_count < 2) {                                  \
        Read_ahead_buf[Read_ahead_count++] = c;                    \
      } else {                                                     \
        Data_overrun_errors += 1;                                  \
        Where_data_overrun = WHERE_CHECK_SYNC_SEEN2;               \
      }                                                            \
    } /* end if (byte received) */                                 \
    if (Recv_buf == Send_buf) {                                    \
      /* Switch receive buffer. */                                 \
      if (Bytep <= Endp) {                                         \
        Incomplete_bufs += 1;                                      \
        Where_incomplete = WHERE_CHECK_SYNC_SEEN1;                 \
      }                                                            \
      Recv_buf ^= 1;                                               \
      Recv_start = Bytep = Buffer[Recv_buf];                       \
      Endp = Bytep + 799;                                          \
      for (byte i = 0; i < Read_ahead_count; i++) {                \
        *Bytep++ = Read_ahead_buf[i];                              \
      }                                                            \
      Read_ahead_count = 0;                                        \
      Recv_ok = 1;                                                 \
      Sync_seen = 0;                                               \
      PORTC = 0;                                                   \
    } else if (Bytep - Recv_start < MIN_BYTES) {                   \
      /* incomplete results, truncate it */                        \
      Incomplete_bufs += 1;                                        \
      Where_incomplete = WHERE_CHECK_SYNC_SEEN2;                   \
      Bytep = Recv_start;                                          \
      for (byte i = 0; i < Read_ahead_count; i++) {                \
        *Bytep++ = Read_ahead_buf[i];                              \
      }                                                            \
      Read_ahead_count = 0;                                        \
      Recv_ok = 1;                                                 \
      Sync_seen = 0;                                               \
      PORTC = 0;                                                   \
    }                                                              \
  } /* end if (Sync_seen) */

// Called from:
//   * send_2_bytes
//   * send_frame
#define MAG_CHECK(last_statement)                       \
  if (!(PIND & 0x90) && TCNT1 > 5000) {                 \
    /* mag & switch closed == sync mode */              \
    GTCCR = 1; /* reset timer0-1 prescaler */           \
    unsigned int rotation = TCNT1;                      \
    TCNT1 = 0;                                          \
    Slice = (rotation + 25u) / 50u;                     \
    Rotation = rotation;                                \
    Send_buf ^= 1;                                      \
    if (Recv_buf == Send_buf) {                         \
      /* already receiving into new buffer */           \
      if (Bytep - Recv_start < MIN_BYTES) {             \
        State = WAIT_MIN_BYTES;                         \
      }                                                 \
    } else {                                            \
      /* were still receiving into send buffer! */      \
      Recv_buf = Send_buf;                              \
      Recv_start = Bytep = Buffer[Recv_buf];            \
      Endp = Bytep + 799;                               \
      Recv_ok = 1;                                      \
      PORTC = 0;                                        \
      if (Sync_seen) {                                  \
        for (byte i = 0; i < Read_ahead_count; i++) {   \
          *Bytep++ = Read_ahead_buf[i];                 \
        }                                               \
        Read_ahead_count = 0;                           \
        Sync_seen = 0;                                  \
        State = WAIT_MIN_BYTES;                         \
      } else {                                          \
        State = WAIT_SYNC_START;                        \
      }                                                 \
    }                                                   \
    last_statement;                                     \
  }

#define WAIT_UNTIL(time)                \
  while (TCNT2 < (time)) 

// Called from:
//   * send_slice
//   * send_256
byte
send_2_bytes(byte n1, byte n2) {
  // This takes .1 mSec to execute, or the time for 1 column.
  byte bit = 0x01;
  byte flags;
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
  CHECK_SYNC_SEEN(flags);
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
  while (TCNT2 < 200) { // includes extra wait time for .1 mSec/column
    RECV_TEST(flags);
    CHECK_SYNC_SEEN(flags);
    MAG_CHECK(return 1);
  }
  return 0;
}

// Called from:
//   * send_frame
byte
send_slice(byte *p) {
  // This function takes .8 mSec to run.
  for (byte i = 0; i < 16; i += 2) {
    if (send_2_bytes(p[i], p[i+1])) return 1;
  }
  return 0;
}

// Called from:
//   * SEND state
byte
send_frame(byte *p) {
  // This sends one complete revolution (800 bytes).
  // Timer1 (TCNT1) has been zeroed at the start of the revolution.
  // Slice holds the number of Timer1 ticks per slice.
  unsigned int end_time = Slice;
  for (int i = 0; i < 800; i += 16) {
    if (send_slice(p + i)) return 1;
    // There should be at least .2 mSec of idle time here:
    while (TCNT1 < end_time) {
      byte flags;
      RECV_TEST(flags);
      CHECK_SYNC_SEEN(flags);
      MAG_CHECK(return 1);
    } // end while (TCNT2 < end_time)
    end_time += Slice;
  } // end for (i)
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
  byte flags;
  switch (State) {
  case WAIT_SYNC_START:
    // From program start
    //    and SEND if end of frame and still receiving into Send_buf
    // Pre-conditions:
    //    * no SYNC_CHAR seen
    //    * no received data
    //    * no MAG seen
    // Next States:
    //    * WAIT_MIN_BYTES if SYNC_CHAR seen
    if (flags = (UCSR0A & ((1 << RXC0) | (1 << FE0) | (1 << DOR0)))) {
      byte c = UDR0;
      if (flags & (1 << FE0)) {
        Framing_errors += 1;
        Where_framing_error = WHERE_WAIT_SYNC_START;
      }
      if (flags & (1 << DOR0)) {
        Data_overrun_errors += 1;
        Where_data_overrun = WHERE_WAIT_SYNC_START;
      }
      if (Ignore_next_escape) Ignore_next_escape = 0;
      else if (c == ESC_CHAR) Ignore_next_escape = 1;
      else if (c == SYNC_CHAR) State = WAIT_MIN_BYTES;
    }
    if (!(PIND & 0x80) && TCNT1 > 5000) {
      // mag sensor
      GTCCR = 1; // reset timer0-1 prescaler
      unsigned int rotation = TCNT1;
      TCNT1 = 0;
      print_rps(rotation);
    }
    if (!(PIND & 0x20)) { // push button down
      send_256();
      TCNT1 = 0;
      while (TCNT1 < 62500u) ;    // delay 250 mSec
      TCNT1 = 0;
      while (TCNT1 < 62500u) ;    // delay 250 mSec
    }
    break;
  case WAIT_MIN_BYTES:
    // From WAIT_SYNC_START when SYNC_CHAR seen
    //    and SEND if end of frame and < MIN_BYTES in next Send_buf
    // Pre-conditions:
    //    * SYNC_CHAR seen
    //    * < MIN_BYTES received data
    //    * no MAG seen
    // Next States:
    //    * WAIT_MAG when MIN_BYTES received
    if (flags = (UCSR0A & ((1 << RXC0) | (1 << FE0) | (1 << DOR0)))) {
      byte c = UDR0;
      if (flags & (1 << FE0)) {
        Framing_errors += 1;
        Where_framing_error = WHERE_WAIT_MIN_BYTES;
      }
      if (flags & (1 << DOR0)) {
        Data_overrun_errors += 1;
        Where_data_overrun = WHERE_WAIT_MIN_BYTES;
      }
      if (Ignore_next_escape) {
        Ignore_next_escape = 0;
        *Bytep++ = c;
      } else if (c == ESC_CHAR) Ignore_next_escape = 1;
      else if (c == SYNC_CHAR) {
        // incomplete, truncate data and stay in same receive buffer
        Incomplete_bufs += 1;
        Where_incomplete = WHERE_WAIT_MIN_BYTES;
        Bytep = Recv_start;
      } else {
        *Bytep++ = c;
      }
      if (Bytep - Recv_start > MIN_BYTES) {
        State = WAIT_MAG;
      }
    } // end if (byte received)
    if (!(PIND & 0x80) && TCNT1 > 5000) {
      // mag sensor
      GTCCR = 1; // reset timer0-1 prescaler
      unsigned int rotation = TCNT1;
      TCNT1 = 0;
      print_rps(rotation);
    }
    break;
  case WAIT_MAG:
    // From WAIT_MIN_BYTES when MIN_BYTES received.
    //    and SEND if end of frame and >= MIN_BYTES in next Send_buf
    // Pre-conditions:
    //    * SYNC_CHAR seen
    //    * >= MIN_BYTES received data
    //    * no MAG seen
    // Next States:
    //    * SEND if MAG seen
    //    * WAIT_MAG2 if both buffers full and SYNC_CHAR seen
    if (flags = (UCSR0A & ((1 << RXC0) | (1 << FE0) | (1 << DOR0)))) {
      byte c = UDR0;
      if (flags & (1 << FE0)) {
        Framing_errors += 1;
        Where_framing_error = WHERE_WAIT_MAG;
      }
      if (flags & (1 << DOR0)) {
        Data_overrun_errors += 1;
        Where_data_overrun = WHERE_WAIT_MAG;
      }
      if (Ignore_next_escape) {
        Ignore_next_escape = 0;
        if (Bytep <= Endp) *Bytep++ = c;
        else {
          Buf_overflows += 1;
          Where_overflow = WHERE_WAIT_MAG;
        }
      } else if (c == ESC_CHAR) Ignore_next_escape = 1;
      else if (c == SYNC_CHAR) {
        if (Bytep - Recv_start < MIN_BYTES) {
          Incomplete_bufs += 1;
          Where_incomplete = WHERE_WAIT_MAG1;
          Bytep = Recv_start;  // incomplete, throw data away
        } else if (Recv_buf == Send_buf) {
          if (Bytep <= Endp) {
            Incomplete_bufs += 1;
            Where_incomplete = WHERE_WAIT_MAG2;
          }
          Recv_buf ^= 1;
          Bytep = Recv_start = Buffer[Recv_buf];
          Endp = Bytep + 799;
        } else {
          PORTC = 1;
          Recv_ok = 0;
          Sync_seen = 1;
          State = WAIT_MAG2;
        }
      } else if (Bytep <= Endp) *Bytep++ = c;
    } // end if (byte received)
    if ((!(PIND & 0x80) && TCNT1 > 5000) || (PIND & 0x10)) {
      // mag pickup || switch in async mode
      GTCCR = 1;  // reset timer0-1 prescalar
      if (PIND & 0x10) {
        // switch in async mode
        Rotation = 12500;        // 50mSec
        Slice = 250;             // 1mSec
        TCNT1 = 0;
      } else {
        unsigned int rotation = TCNT1;
        TCNT1 = 0;
        Slice = (rotation + 25u) / 50u;
        Rotation = rotation;
        print_rps(rotation);
      }
      State = SEND;
    }
    break;
  case WAIT_MAG2:
    // From WAIT_MAG when both buffers full and SYNC_CHAR seen.
    // Pre-conditions:
    //    * SYNC_CHAR seen (unprocessed)
    //    * both buffers full
    //    * no MAG seen
    // Next States:
    //    * SEND if MAG seen

    if (flags = (UCSR0A & ((1 << RXC0) | (1 << FE0) | (1 << DOR0)))) {
      byte c = UDR0;
      if (flags & (1 << FE0)) {
        Framing_errors += 1;
        Where_framing_error = WHERE_WAIT_MAG2;
      }
      if (flags & (1 << DOR0)) {
        Data_overrun_errors += 1;
        Where_data_overrun = WHERE_WAIT_MAG2;
      }
      if (Read_ahead_count < 2) {
        Read_ahead_buf[Read_ahead_count++] = c;
      } else {
        Data_overrun_errors += 1;
        Where_data_overrun = WHERE_WAIT_MAG2;
      }
    } // end if (byte received)

    if ((!(PIND & 0x80) && TCNT1 > 5000) || (PIND & 0x10)) {
      // mag pickup || switch in async mode
      GTCCR = 1;  // reset timer0-1 prescalar
      if (PIND & 0x10) {
        // switch in async mode
        Rotation = 12500;        // 50mSec
        Slice = 250;             // 1mSec
        TCNT1 = 0;
      } else {
        unsigned int rotation = TCNT1;
        TCNT1 = 0;
        Slice = (rotation + 25u) / 50u;
        Rotation = rotation;
        print_rps(rotation);
      }
      State = SEND;
    } // end if (mag pickup || switch in async mode)
    break;
  case SEND:
    // From WAIT_MAG or WAIT_MAG2 when mag pickup seen (or async mode)
    // Pre-conditions:
    //    * >= MIN_BYTES in Send_buf
    //    * MAG seen
    // Next States (both from MAG_CHECK):
    //    * WAIT_SYNC_START if end of frame and still receiving into Send_buf
    //    * WAIT_MIN_BYTES if end of frame and < MIN_BYTES in next Send_buf
    //    * WAIT_MAG if end of frame and >= MIN_BYTES in next Send_buf
    if (!send_frame(Buffer[Send_buf])) {
      Send_buf ^= 1;
      if (Recv_buf != Send_buf) {
        // hosed!  We've finished sending the buffer before it's been received!
        Incomplete_bufs += 1;
        Where_incomplete = WHERE_SEND;
        Recv_buf = Send_buf;
        Bytep = Recv_start = Buffer[Recv_buf];
        Endp = Bytep + 799;
        State = WAIT_SYNC_START;
      } else if (Bytep - Recv_start < MIN_BYTES) {
        State = WAIT_MIN_BYTES;
      } else State = WAIT_MAG;
      // print_errors();
    } // end if (!send_frame(...))
    break;
  } // end switch (State)
}
