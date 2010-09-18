// pulse

// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

unsigned long
calc_ocr2a(unsigned long rate, unsigned N) {
  /*******
    foc2A = fclk / (N*(1+OCR2A))   where N is prescalar value
    N*(1+OCR2A) = fclk/foc2A
    1+OCR2A = fclk/(N*foc2A)
    OCR2A = fclk/(N*foc2A) - 1
  ********/
  return (16000000L + N * rate / 2) / (N * rate) - 1;
}

unsigned Prescalar[] = {0, 1, 8, 32, 64, 128, 256, 1024};

void
set_rate(unsigned long rate, unsigned long pw_clocks) {
  byte i;
  for (i = 1; i <= 7; i++) {
    unsigned long ocr2a = calc_ocr2a(rate, Prescalar[i]);
    if (ocr2a < 255) {
      byte ocr2a_byte = byte(ocr2a);
      TCCR2B = 8 | i;
      OCR2A = ocr2a_byte;
      unsigned long divisor = Prescalar[i] * (1 + (unsigned long)ocr2a_byte);
      unsigned long resulting_rate = (16000000L + divisor / 2) / divisor;
      byte ocr2b = byte((pw_clocks + Prescalar[i] / 2) / Prescalar[i]);
      if (ocr2b < 1) ocr2b = 1;
      OCR2B = ocr2b;
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
      Serial.println(resulting_rate);
      break;
    }
  }
}

unsigned long Rate = 12500;
unsigned long PW_clocks = 16 * 40;
unsigned long Num;

void
setup(void) {
  Serial.begin(57600);
  //pinMode(11, OUTPUT);  // OCR2A, PB3
  pinMode(3, OUTPUT);  // OCR2B, PD3
  TIMSK2 = 0;
  ASSR = 0;
  //TCCR2A = 0x42;
  TCCR2A = 0x23;
  set_rate(Rate, PW_clocks);
}

void
loop(void) {
  /***
  if (Serial.available()) {
    byte c = Serial.read();
    if (c == '.') {
      Rate = Num;
      set_rate(Rate, PW_clocks);
      Num = 0;
    } else if (c == ';') {
      PW_clocks = Num;
      set_rate(Rate, PW_clocks);
      Num = 0;
    } else Num = 10 * Num + (c - '0');
  }
  ***/
}
