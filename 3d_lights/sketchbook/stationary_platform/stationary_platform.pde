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

unsigned long Start_mag_time;   // time (in uSec) of last magnetic pulse
unsigned long Rotation;         // uSec/rotation
unsigned int  Slice;            // uSec/slice

void
help(void) {
  Serial.println(".  -- send all 256 chars as a block");
  Serial.println("+  -- send infinite 0x55 chars, RESET to stop");
  Serial.println("xx -- send hex xx char");
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

  // Set up timer 2 to tick at .5 uSec/tick.
  TIMSK0 = 0;     // disable interrupts
  TCCR2A = 0;     // WGM = 0 (normal mode)
  TCCR2B = 0x02;  // prescaler: timer clk == cpu clk / 8
  ASSR = 0;

  help();
}

byte Buffer[2][800];
byte Recv_buf = 0;
byte *Bytep = &Buffer[Recv_buf];
byte *Endp = Bytep + 799;    // Set to last byte position to accept data into

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
  PORTD = bit;                          \
  bit = ~(n & 1);                       \
  n >>= 1;                              \
  PORTD = 0;                            \
  RECV_TEST()

#define MAG_CHECK()                     \
  if (PIND & 0x80) {
    unsigned long rotation = micros() - Start_mag_time;
    if (rotation > 20000ul) {
      Rotation = rotation;
      Slice = (rotation + 25ul) / 50ul;
      Start_mag_time = now;
    }
  }

#define WAIT_UNTIL(time)                \
  while (TCNT2 < (time)) 

void
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
  MAG_CHECK();
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
  MAG_CHECK();
  WAIT_UNTIL(200);      // includes extra wait time for .1 mSec/column
}

void
send_slice(byte *p) {
  for (byte i = 0; i < 15; i += 2) {
    send_2_bytes(p[i], p[i+1]);
  }
  // delay .2 mSec (sync pause at end of slice)
  unsigned long start_time = micros();
  while (micros() - start_time < 200ul) {
    // There may be up to 2 bytes left to recv.
    if ((PORTC & 1) && Bytep <= Endp) PORTC = 0;
    RECV_TEST();
  }
}

void
send_frame(byte *p) {
  unsigned long start_time = micros();
  for (int i = 0; i < 800; i += 16) {
    send_slice(p + i);
    if (PIND & 0x10) {
      unsigned long end_time;
      while ((end_time = micros()) - start_time < Slice) ;
      start_time = end_time;
    }
  }
}

byte
hex(byte c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return c - 'A' + 10;
}

byte c1;

void
send_256(void) {
  Serial.println("Sending all 256 chars");
  for (byte i = 0; i < 255; i += 2) {
    send_2_bytes(i, i + 1);
  }
  Serial.println("sent");
}

void
loop(void) {
  if (Bytep >= Endp) {
    byte *p = &Buffer[Recv_buf];
    Recv_buf ^= 1;
    Bytep = Buffer[Recv_buf];
    Endp = Bytep + 799;
    send_frame(p);
  } else RECV_TEST()
  else if (button) {
    send_256();
  }
}
