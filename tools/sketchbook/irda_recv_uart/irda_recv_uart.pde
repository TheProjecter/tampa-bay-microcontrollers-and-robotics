
// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

byte Prescalar;

void
help() {
  Serial.println("h - help");
}

void
setup(void) {
  Serial.begin(57600);
  //pinMode(11, OUTPUT);  // OCR2A, PB3
  
  Serial.print("Timer0 prescalar ");
  Serial.println(TCCR0B & 0x07, DEC);
  
  //pinMode(8, OUTPUT);
  
  help();
  Serial.begin(250000);
}

byte Bytes[256];
int  Num_bytes;

#define TEST_LEN 256

void
loop(void) {
  if (Serial.available()) {
    Bytes[Num_bytes++] = Serial.read();
  }
  if (Num_bytes >= TEST_LEN) {
    Num_bytes = 0;
    Serial.begin(57600);
    if (TEST_LEN > 1) {
      int Errors = 0;
      for (int i = 0; i < TEST_LEN; i++) {
        Serial.println(Bytes[i], HEX);
        if (Bytes[i] != i) Errors++;
      }
      Serial.print(Errors);
      Serial.println(" errors");
    } else {
      Serial.print("0x");
      Serial.println(Bytes[0], HEX);
      Serial.println(Prescalar, DEC);
    }
    Serial.begin(250000);
  }
}
