
#include <avr/io.h>

void
setup(void) {
  Serial.begin(57600);
  pinMode(11, OUTPUT);  // OCR2A, PB3
  TIMSK2 = 0;
  ASSR = 0;
  TCCR2A = 0x42;
}

unsigned long
calc_ocr2a(unsigned long rate, unsigned N) {
  /*******
    foc2A = fclk / (2*N*(1+OCR2A))   where N is prescalar value
    we nuke the 2, because we want baud rate...
    N*(1+OCR2A) = fclk/foc2A
    1+OCR2A = fclk/(N*foc2A)
    OCR2A = fclk/(N*foc2A) - 1
  ********/
  return (16000000L + N * rate / 2) / (N * rate) - 1;
}

unsigned Prescalar[] = {0, 1, 8, 32, 64, 128, 256, 1024};

void
set_rate(unsigned long rate) {
  byte i;
  for (i = 1; i <= 7; i++) {
    unsigned long ocr2a = calc_ocr2a(rate, Prescalar[i]);
    if (ocr2a < 255) {
      byte ocr2a_byte = byte(ocr2a);
      TCCR2B = i;
      OCR2A = ocr2a_byte;
      Serial.print("Setting rate to ");
      Serial.print(rate);
      Serial.println(" baud");
      Serial.print("Prescalar ");
      Serial.print(Prescalar[i]);
      Serial.print("[");
      Serial.print(i, DEC);
      Serial.print("], OCR2A ");
      Serial.println(ocr2a_byte, DEC);
      Serial.print("Resulting baud ");
      unsigned long divisor = Prescalar[i] * (1 + (unsigned long)ocr2a_byte);
      Serial.println((16000000L + divisor / 2) / divisor);
      break;
    }
  }
}

unsigned long Rate;

void
loop(void) {
  if (Serial.available()) {
    byte c = Serial.read();
    if (c == '.') {
      set_rate(Rate);
      Rate = 0;
    } else Rate = 10 * Rate + (c - '0');
  }
}
