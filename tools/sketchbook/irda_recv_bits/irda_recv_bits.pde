
// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

unsigned long ding_time;

void
setup(void) {
  Serial.begin(57600);
  //pinMode(11, OUTPUT);  // OCR2A, PB3
  
  Serial.print("Timer0 prescalar ");
  Serial.println(TCCR0B & 0x07, DEC);
  
  pinMode(2, INPUT);      // INT0, PD2
  digitalWrite(2, HIGH);   // disable pull-up resistor
  pinMode(8, OUTPUT);
  
  // Set up timer 2 to interrupt every 5 uSec (using TOV2 interrupt):
  TIMSK2 = 0;     // disable TOV2 interrupt
  TCCR2A = 0x03;  // WGM = 7 (Fast PWM  mode, TOP = OCR2A)
  TCCR2B = 0x09;  // no prescaler: timer clk == cpu clk
  ASSR = 0;
  OCR2A = 79;     // 5 uSec between TOV2
  EICRA = 0x03; // INT0 -> 2 falling edge, 3 rising edge
  EIFR = 1;     // reset interrupt flag for INT0
  EIMSK = 1;    // enable INT0
  ding_time = millis() + 500;
  interrupts(); // Global enable interrupts
  
  //TIMSK2 = 1;   // test...
  //EIMSK = 0;
}

unsigned long Num_starts = 0;
unsigned long Num_timer2 = 0;
byte Started = 0;
byte B;
byte Count;
byte Bit;

byte Bytes[256];
int  Num_bytes;

ISR(INT0_vect) {
  if (Started == 0) {
    TCNT2 = 0;
    //Num_starts++;
    Started = 1;
    Count = 8;
    B = 0;
    Bit = 0;
    while (TCNT2 < 10) ;   // offset counter 1/2 bit
    TCNT2 = 0;
    PINB = 1;
    TIFR2 = 1;  // reset TIMER2_OVF interrupt
    TIMSK2 = 1; // enable TIMER2_OVF interrupt
  } else {
    Bit = 1;
  }
}

ISR(TIMER2_OVF_vect) {
  PINB = 1;
  B = (B << 1) | Bit;
  Bit = 0;
  //Num_timer2++;
  if (--Count == 0) {
    Started = 0;
    TIMSK2 = 0;   // disable TIMER2_OVF interrupt
    TIFR2 = 1;    // clear pending interrupt (if any)
    Bytes[Num_bytes++] = B;
  }
}

#define TEST_LEN 1

byte ding_on;

void
loop(void) {
  if (Num_bytes >= TEST_LEN) {
    Num_bytes = 0;
    int Errors = 0;
    for (int i = 0; i < TEST_LEN; i++) {
      Serial.println(Bytes[i], HEX);
      if (Bytes[i] != i) Errors++;
    }
    //Serial.print(Errors);
    //Serial.println(" errors");
  } else if (Serial.available()) {
    ding_on = Serial.read() == '+';
  } else if (ding_on && millis() > ding_time) {
    Serial.print("Num_starts ");
    Serial.print(Num_starts);
    Serial.print(", Num_timer2 ");
    Serial.println(Num_timer2);
    ding_time += 500;
  }
}
