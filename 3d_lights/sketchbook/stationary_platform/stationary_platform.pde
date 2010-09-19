// stationary_platform.pde

// These are grouped on the same port (PORTD) so they can be sampled together:
#define SLIDE_SWITCH_PIN        4
#define PUSH_BUTTON_PIN         5
#define MAGNETIC_PICKUP_PIN     7

// The IRDA_TX_PIN is bit 0 of PORTB:
#define IRDA_TX_PIN             8
#define IRDA_SD_PIN             9

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
  
  // Set up timer 2 to tick at .5 uSec/tick.
  TIMSK0 = 0;     // disable interrupts
  TCCR2A = 0;     // WGM = 0 (normal mode)
  TCCR2B = 0x02;  // prescaler: timer clk == cpu clk / 8
  ASSR = 0;

  help();
}

byte Buffer[2][50][16];

#define send_bit(time)    \
  PORTD = bit;            \
  bit = ~(n & 1);         \
  n >>= 1;                \
  PORTD = 0;              \
  while (TCNT2 < time) 

void
send_byte(byte n) {
  byte bit = 0x01;
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
send_256(void) {
  Serial.println("Sending all 256 chars");
  for (int i = 0; i < 256; i++) {
    send_byte(byte(i));
  }
  Serial.println("sent");
}

void
loop(void) {
  if (Serial.available()) {
    byte c = Serial.read();
    if (c == '.') {

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
