// timer2_demo.pde

// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

void
help(void) {
  Serial.println("t  - run test");
}

void
setup(void) {
  Serial.begin(57600);

  // set up Timer2 in normal mode with prescaler of 32 (2uSec per timer tick).
  // TCNT2 has timer count.
  // GTCCR = 2 to reset prescaler count
  OCR2A = 49;     // .1mSec (100uSec)
  OCR2B = 74;     // .15mSec (150uSec)
  ASSR = 0;
  TIMSK2 = 0;     // disable interrupts
  TCCR2A = 0x03;  // Fast PWM mode (this doesn't work in normal mode (== 0x00)!)
  TCCR2B = 0x03;  // prescaler = 32

  interrupts();
  Serial.println("timer2 demo");
  help();
}

unsigned long A_time;
unsigned long B_time;

ISR(TIMER2_COMPA_vect) {
  TIMSK2 = 0x04;   // disable compare match OCR2A interrupt,
                   // leave OCR2B match enabled.
  A_time = micros();
}

ISR(TIMER2_COMPB_vect) {
  TIMSK2 = 0;     // disable compare match OCR2A and OCR2B interrupt
  B_time = micros();
}

void
test(void) {
  A_time = B_time = 0ul;
  unsigned long start_time = micros();
  GTCCR = 2;     // reset prescalar for timer2
  TCNT2 = 0;     // set timer2 value to 0
  TIFR2 = 6;     // reset OCF2A and OCF2B match flags
  TIMSK2 = 0x06; // enable compare match OCR2A and OCR2B interrupt
  while (micros() - start_time < 2000) ;
  TIMSK2 = 0;     // disable compare match OCR2A and OCR2B interrupt
  Serial.print("start_time ");
  Serial.println(start_time);
  Serial.print("A_time ");
  Serial.print(A_time);
  if (A_time) {
    Serial.print(" ");
    Serial.println(A_time - start_time);
  } else Serial.println(" ");
  Serial.print("B_time ");
  Serial.print(B_time);
  if (B_time) {
    Serial.print(" ");
    Serial.println(B_time - start_time);
  } else Serial.println(" ");
}

void
loop(void) {
  if (Serial.available()) {
    byte c = Serial.read();
    if (c == 't') test();
    else if (c == 'h') help();
  }
}
