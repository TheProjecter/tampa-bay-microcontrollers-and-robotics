// rotating_platform_test.pde

// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

/********************************************************
Pin assignments:

  OCR2A LED pin 7         PORTD pin 0x80
  OCR2B LED pin 8         PORTB pin 0x01
  TOV       analog pin 0  PORTC pin 0x01

*********************************************************/

#define TCCR2A_SETTING  0x03   /* fast PWM mode */
//#define TCCR2A_SETTING  0x00   /* normal mode */
#define TCCR2B_SETTING  0x03   /* prescaler = 32 */

byte B = 0x1E;
byte C = 0x3E;
byte D = 0x7C;

byte Post_reset_TIFR2;
byte A_TCNT2;
byte A_PIND;
byte B_TCNT2;
byte B_PINB;
byte Loop_A_PORTD;
byte Loop_B_PORTB;

void
reset_timer2(void) {
  GTCCR = 2;     // reset prescalar for timer2
  TCNT2 = 255;   // set timer2 value to 0xFF
  TIFR2 = 6;     // reset OCF2A and OCF2B match flags
  Post_reset_TIFR2 = TIFR2;
  //TCCR2A = TCCR2A_SETTING;
  //TCCR2B = TCCR2B_SETTING;
  PORTD = D;
  PORTB = B;
  TIMSK2 = 0x06; // enable compare match OCR2A and OCR2B interrupt
  A_TCNT2 = 0;
  B_TCNT2 = 0;
  A_PIND = 0;
  B_PINB = 0;
  Loop_A_PORTD = 0;
  Loop_B_PORTB = 0;
}

ISR(TIMER2_COMPA_vect) {
  A_TCNT2 = TCNT2;
  PORTD = 0xFC;    // pin 7
  TIMSK2 = 0x04;   // disable compare match OCR2A interrupt,
                   // leave OCR2B match enabled.
  A_PIND = PIND;
}

ISR(TIMER2_COMPB_vect) {
  B_TCNT2 = TCNT2;
  PORTB = 0x1F;   // pin 8
  TIMSK2 = 0;     // disable compare match OCR2A and OCR2B interrupt
  B_PINB = PINB;
}

void
setup(void) {
  // turn off pull-ups, set output ports LOW
  PORTB = 0;
  PORTC = 0;
  PORTD = 0;

  DDRD = 0x80;    // 1 output pin, 7
  DDRB = 0x21;    // 2 output pins, 8 and 13
  DDRC = 0x01;    // 1 output pin, 0
  PORTD = D;      // enable pullup on all pins, except 7, 1 and 0
  PORTB = B;      // enable pullup on all pins, except 8
  PORTC = C;      // enable pullup on all analog pins

  Serial.begin(57600);

  // set up Timer2 in normal mode with prescaler of 32 (2uSec per timer tick).
  // TCNT2 has timer count.
  // GTCCR = 2 to reset prescaler count
  OCR2A = 48;     // .1mSec (100uSec)
  OCR2B = 73;     // .15mSec (150uSec)
  ASSR = 0;
  TIMSK2 = 0;     // disable interrupts
  //TIMSK2 = 0x06;  // enable interrupts
  TCCR2A = TCCR2A_SETTING;
  TCCR2B = TCCR2B_SETTING;

  /************************
  // set up USART for 250K, 8-N-1, no interrupts
  UBRR0H = 0;
  UBRR0L = 3;     // 250K baud
  UCSR0A = 0x00;  // turn off double speed and multi-processor mode
  UCSR0C = 0x06;  // 8-N-1
  UCSR0B = 0x10;  // enable receiver, disable transmitter, disable all intr
  *************************/
  
  interrupts();
  reset_timer2();
  //TIMSK2 = 0x06;  // enable interrupts
}

byte Count = 3;

void
loop(void) {
  if (TCNT2 == 52) Loop_A_PORTD = PIND;
  else if (TCNT2 == 77) Loop_B_PORTB = PINB;
  else if (TCNT2 == 100) {   // 200uSec
    //TIMSK2 = 0;  // disable compare match OCR2A and OCR2B interrupt
    //TCCR2B = 0;  // turn off timer2

    /**************************
    Serial.println("");
    Serial.print("Post_reset_TIFR2 0x");
    Serial.println(Post_reset_TIFR2, HEX);
    Serial.print("A_TCNT2 ");
    Serial.println(A_TCNT2, DEC);
    Serial.print("A_PIND 0x");
    Serial.println(A_PIND, HEX);
    Serial.print("B_TCNT2 ");
    Serial.println(B_TCNT2, DEC);
    Serial.print("B_PINB 0x");
    Serial.println(B_PINB, HEX);
    Serial.print("Loop_A_PORTD 0x");
    Serial.println(Loop_A_PORTD, HEX);
    Serial.print("Loop_B_PORTB 0x");
    Serial.println(Loop_B_PORTB, HEX);
    //PORTD = 0xFC;
    //Serial.print("PORTD after setting it 0x");
    //Serial.println(PORTD, HEX);
    //Serial.print("PIND after setting it 0x");
    //Serial.println(PIND, HEX);

    if (--Count == 0) for (;;) ;

    **************************/

    //TCCR2B = 0x03;  // prescaler = 32
    //TIMSK2 = 0x06;  // enable compare match OCR2A and OCR2B interrupt

    reset_timer2();

    /****************
    PORTD = D;
    //D ^= 0x80;
    PORTB = B;
    //B ^= 1;
    PORTC = C;
    C ^= 1;
    ****************/
  }
}
