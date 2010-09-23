// uart_sender.pde

// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>

/********************************************************

USART registers:

UDR0    - data register: send/recv data here
UCSR0A  - status register (MSB to LSB):
             RXC0  - set when recv complete
             TXC0  - set when transmit complete (may trigger Trans Compl int)
             UDRE0 - set when data reg ready (for next transmitted byte)
             FE0   - set if framing error
             DOR0  - set if data overrun
             UPE0  - set if parity error
             U2X0  - set for double transmission speed
             MPCM0 - set for multi-processor mode
UCSR0B  - 
             RXCIE0 - set to enable intr on RXC0 flag
             TXCIE0 - set to enable intr on TXC0 flag
             UDRIE0 - set to enable intr on UDRE0 flag
             RXEN0  - set to enable the receiver
             TXEN0  - set to enable the transmitter
             UCSZ02 - char size
             RXB80  - ninth received data bit
             TXB80  - ninth data bit to transmit

UCSR0C  -
             UMSEL01
             UMSEL00 - 00 async, 01 sync, 10 resv, 11 master SPI
             UPM01
             UPM00   - 00 no parity, 01 resv, 10 even parity, 11 odd parity
             USBS0   - 0=1 stop bit, 1=2 stop bits
             UCSZ01    (UCSZ02 in UCSR0B register)
             UCSZ00  - 000 5 bits, 001 6, 010 7, 011 8, 100 & 101 resv, 111 9
             UCPOL0  - 0 for async

UBRR0H  - (only last 4 bits used)
UBRR0L  - baud rate register, 1=500K, 3=250K

*********************************************************/

char *msg1 = "normal pattern sent 2 bytes every 100 uSec";
byte Normal_test1[] = {
  0, 0x55,
  20, 0x55,
  30, 0xaa,
  20, 0xaa,
  30, 0x55,
  20, 0x55,
  30, 0xaa,
  20, 0xaa,
  30, 0x55,
  20, 0x55,
  255
};

char *msg2 = "slower pattern sent 2 bytes every 130 uSec, should still work";
byte Normal_test2[] = {
  0, 0x55,
  35, 0x55,
  30, 0xaa,
  35, 0xaa,
  30, 0x55,
  35, 0x55,
  30, 0xaa,
  35, 0xaa,
  30, 0x55,
  35, 0x55,
  255
};

char *msg3 = "short reset after 1 column";
byte Normal_test3[] = {
  0, 0x55,
  20, 0x55,
  85, 0xaa,             // 170 uSec, these bytes start at column 7 again
  20, 0xaa,
  30, 0x55,
  20, 0x55,
  30, 0xaa,
  20, 0xaa,
  30, 0x55,
  20, 0x55,
  255
};

char *msg4 = "normal reset after 1 column";
byte Normal_test4[] = {
  0, 0x55,
  20, 0x55,
  100, 0xaa,             // 200 uSec, these bytes start at column 7 again
  20, 0xaa,
  30, 0x55,
  20, 0x55,
  30, 0xaa,
  20, 0xaa,
  30, 0x55,
  20, 0x55,
  255
};

char *msg5 = "reset after 1 column and 1 FF byte";
byte Normal_test5[] = {
  0, 0x55,
  20, 0x55,
  30, 0xff,             // shouldn't see this byte!
  65, 0xaa,             // 170 uSec for 2nd byte, should reset and these next
                        // 2 bytes start at column 7 again
  20, 0xaa,
  30, 0x55,
  20, 0x55,
  30, 0xaa,
  20, 0xaa,
  30, 0x55,
  20, 0x55,
  255
};

void
help(void) {
  Serial.println("uart_sender:");
  Serial.println("  0 - comm test, 0 errors");
  Serial.println("  1 - comm test, 1 error");
  Serial.println("  2 - comm test, 2 errors");
  Serial.println("  3 - comm test, 3 errors");
  Serial.println("  a - normal test:");
  Serial.print("      ");
  Serial.println(msg1);
  Serial.println("  b - normal test:");
  Serial.print("      ");
  Serial.println(msg2);
  Serial.println("  c - normal test:");
  Serial.print("      ");
  Serial.println(msg3);
  Serial.println("  d - normal test:");
  Serial.print("      ");
  Serial.println(msg4);
  Serial.println("  e - normal test:");
  Serial.print("      ");
  Serial.println(msg5);
}

void
setup(void) {
  Serial.begin(57600);

  // set up Timer2 in normal mode with prescaler of 32 (2 uSec per timer tick).
  // TCNT2 has timer count.
  // GTCCR = 2 to reset prescaler count
  ASSR = 0;
  TIMSK2 = 0;     // disable interrupts
  TCCR2A = 0x00;  // normal mode
  TCCR2B = 0x03;  // prescaler = 32

  // set up USART1 for 250K, 8-N-1, no interrupts
  UBRR1H = 0;
  UBRR1L = 3;     // 250K baud
  UCSR1A = 0x00;  // turn off double speed and multi-processor mode
  UCSR1C = 0x06;  // 8-N-1
  UCSR1B = 0x08;  // enable transmitter, disable receiver, disable all intr
}

void
comm_test(byte errors) {
  Serial.print("starting comm test with ");
  Serial.print(errors, DEC);
  Serial.println(" errors");
  for (int i = 0; i < 256; i++) {
    byte c = byte(i);
    if (errors >= 1 && c == 10) c = 11;
    if (errors >= 2 && c == 20) c = 22;
    if (errors >= 3 && c == 30) c = 33;
    while (!(UCSR1A & (1 << UDRE1))) ;
    UDR1 = c;
  }
  Serial.println("done");
}

void
normal_test(byte *plan, char *msg) {
  Serial.print("starting normal test ");
  Serial.println(msg);
  byte c = plan[0];
  while (c != 255) {
    TCNT2 = 0;
    GTCCR = 2;  // reset timer2 prescaler
    while (TCNT2 < c) ;
    while (!(UCSR1A & (1 << UDRE1))) ;
    UDR1 = plan[1];
    plan += 2;
    c = plan[0];
  }
  Serial.println("done");
}

void
loop(void) {
  if (Serial.available()) {
    byte c = Serial.read();
    switch (c) {
    case '0':
      comm_test(0);
      break;
    case '1':
      comm_test(1);
      break;
    case '2':
      comm_test(2);
      break;
    case '3':
      comm_test(3);
      break;
    case 'a':
      normal_test(Normal_test1, msg1);
      break;
    case 'b':
      normal_test(Normal_test2, msg2);
      break;
    case 'c':
      normal_test(Normal_test3, msg3);
      break;
    case 'd':
      normal_test(Normal_test4, msg4);
      break;
    case 'e':
      normal_test(Normal_test5, msg5);
      break;
    default:
      help();
      break;
    } // end switch (c)
  } // end if (Serial.available())
}
