// irda_send


// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

void
help(void) {
  Serial.println(".  -- send all 256 chars as a block");
  Serial.println("+  -- send infinite 0x55 chars, RESET to stop");
  Serial.println("xx -- send hex xx char");
  Serial.println("h  -- help");
}

void
setup(void) {
  Serial.begin(57600);
  //pinMode(11, OUTPUT);  // OCR2A, PB3
  pinMode(3, OUTPUT);     // INT0, PD2
  digitalWrite(3, LOW);   // default LOW
  
  // Set up timer 2 with prescaler of 8 (.5 uSec/timer tick)
  TIMSK0 = 0;     // disable interrupts
  TCCR2A = 0;     // WGM = 0 (normal mode)
  TCCR2B = 0x02;  // prescaler: timer clk == cpu clk / 8
  ASSR = 0;
  help();
}

#define send_bit(time)           \
  PORTD = bit;                   \
  bit = (n & 1) ? 0 : 0x08;      \
  n >>= 1;                       \
  PORTD = 0;                     \
  while (TCNT2 < time) 

void
send_byte(byte n) {
  byte bit = 0x08;
  GTCCR = 2;         // reset timer2 prescalar
  TCNT2 = 0;         // reset timer2 counter
  send_bit(8+1);     // start bit
  send_bit(2*8+1);   // bit 7
  send_bit(3*8+1);   // bit 6
  send_bit(4*8+1);   // bit 5
  send_bit(5*8+1);   // bit 4
  send_bit(6*8+1);   // bit 3
  send_bit(7*8+1);   // bit 2
  send_bit(8*8+1);   // bit 1
  send_bit(10*8);    // bit 0 + stop bit
}

byte
hex(byte c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return c - 'A' + 10;
}

byte c1;

void
loop(void) {
  if (Serial.available()) {
    byte c = Serial.read();
    if (c == '.') {
      Serial.println("Sending all 256 chars");
      for (int i = 0; i < 256; i++) {
        send_byte(byte(i));
      }
      Serial.println("sent");
      c1 = 0;
    } else if (c == '+') {
      Serial.println("Sending infinite 0x55, RESET to stop");
      for (;;) send_byte(0x55);
    } else if (c == 'h') {
      help();
      c1 = 0;
    } else if (c1) {
      c1 = (hex(c1) << 4) | hex(c);
      Serial.print("Sending 0x");
      Serial.println(c1, HEX);
      send_byte(c1);
      c1 = 0;
    } else c1 = c;
  }
}
