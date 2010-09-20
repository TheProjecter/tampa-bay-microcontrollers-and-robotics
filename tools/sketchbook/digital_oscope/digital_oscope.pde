// digital_oscope

// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

void
help(void) {
  Serial.println("g - go at 190 nSec sample rate (total 288 mSec)");
}

void
setup(void) {
  Serial.begin(57600);
  //pinMode(11, OUTPUT);  // OCR2A, PB3
  pinMode(8, INPUT);      // PORTB, PIN 0
  digitalWrite(8, LOW);   // no pull-up resistor
  pinMode(9, INPUT);      // PORTB, PIN 1
  digitalWrite(9, LOW);   // no pull-up resistor
  pinMode(10, INPUT);     // PORTB, PIN 2
  digitalWrite(10, LOW);  // no pull-up resistor
  pinMode(11, INPUT);     // PORTB, PIN 3
  digitalWrite(11, LOW);  // no pull-up resistor
  pinMode(12, INPUT);     // PORTB, PIN 4
  digitalWrite(12, LOW);  // no pull-up resistor
  pinMode(13, INPUT);     // PORTB, PIN 5
  digitalWrite(13, LOW);  // no pull-up resistor
  
  // Set up timer 2 to interrupt every 5 uSec (using TOV2 interrupt):
  //TIMSK0 = 0;     // disable interrupts
  //TCCR2A = 0;     // WGM = 0 (normal mode)
  //TCCR2B = 0x02;  // prescaler: timer clk == cpu clk / 8
  //ASSR = 0;
  Serial.println("digital_oscope");
  help();
}

// This will capture DATA_SIZE * 3 / 16 uSec.
// 1.5K is 288uSec.
#define DATA_SIZE   (2+1024+512)

byte Data[DATA_SIZE];

#define get4(i)      \
  Data[i] = PINB;    \
  Data[i+1] = PINB;  \
  Data[i+2] = PINB;  \
  Data[i+3] = PINB

#define get16(i)   \
  get4(i);         \
  get4(i+4);       \
  get4(i+8);       \
  get4(i+12)

#define get64(i)   \
  get16(i);        \
  get16(i+16);     \
  get16(i+32);     \
  get16(i+48)

#define get256(i)  \
  get64(i);        \
  get64(i+64);     \
  get64(i+128);    \
  get64(i+192)

#define get1024(i) \
  get256(i);       \
  get256(i+256);   \
  get256(i+512);   \
  get256(i+768)
  
void
get_data(void) {
  byte b1 = 0, b2;
  while (!((b2 = PINB) & 1)) b1 = b2;
  get1024(2);     // this takes 3 clock cycles per sample
  get256(2+1024);
  get256(2+1024+256);
  Data[0] = b1;
  Data[1] = b2;
}

void
print4(int i) {
  byte d;
  d = i / 1000;
  i %= 1000;
  Serial.print('0' + d);
  d = i / 100;
  i %= 100;
  Serial.print('0' + d);
  d = i / 10;
  i %= 10;
  Serial.print('0' + d);
  Serial.print('0' + i);
}

byte
check_bit(int i, byte bit, byte bytes_output) {
  if ((Data[i-1] & (1 << bit)) != (Data[i] & (1 << bit))) {
    while (bytes_output < 2 * bit) {
      Serial.print(". ");
      bytes_output += 2;
    }
    if (Data[i] & (1 << bit)) {
      Serial.print("+ ");
    } else {
      Serial.print("- ");
    }
    return bytes_output + 2;
  }
  return bytes_output;
}

void
send_data(float sample_rate) {
  for (byte j = 0; j < 6; j++) {
    if (Data[0] & (1 << j)) {
      Serial.print("+ ");
    } else {
      Serial.print("- ");
    }
  }
  Serial.println("pre-trigger");
  int last = 0;
  for (int i = 1; i < DATA_SIZE; i++) {
    byte bytes_output = 0;
    bytes_output = check_bit(i, 0, bytes_output);
    bytes_output = check_bit(i, 1, bytes_output);
    bytes_output = check_bit(i, 2, bytes_output);
    bytes_output = check_bit(i, 3, bytes_output);
    bytes_output = check_bit(i, 4, bytes_output);
    bytes_output = check_bit(i, 5, bytes_output);
    if (bytes_output) {
      while (bytes_output < 12) {
        Serial.print(". ");
        bytes_output += 2;
      }
      Serial.print((i - last) * sample_rate);
      Serial.print(" ");
      Serial.println(i * sample_rate);
      last = i;
    }
  }
}

void
loop(void) {
  if (Serial.available()) {
    byte c = Serial.read();
    switch (c) {
    case 'h':
      help();
      break;
    case 'g':
      Serial.println("waiting");
      get_data();
      send_data(3.0/16.0);
      break;
    }
  }
}
