// digital_oscope.pde

// This header is in /usr/lib/avr/include on Linux and maps to <avr/iom328p.h>
#include <avr/io.h>
#include <avr/pgmspace.h>

char Str_buf[60];

char *
fstr(PGM_P p_str) {
  return strncpy_P(Str_buf, p_str, 59);
}

const char PROGMEM Digital_oscope[] = "digital_oscope:";
const char PROGMEM F_command[] =
  "  f    - fast 190 nSec sample rate (total 288 uSec)";
const char PROGMEM S_command[] =
  "  snn. - slow nn uSec sample rate (total 1.5*nn mSec)";
const char PROGMEM C_command[] =
  "  c    - sample changes (for slow data rates)";

const char PROGMEM Pre_trigger[] = "pre-trigger";
const char PROGMEM Waiting_750_changes[] = "waiting 750 changes";
const char PROGMEM Waiting_fast[] =
  "waiting for 288 mSec sample at 190 nSec sample rate";

const char PROGMEM Waiting1[] = "waiting for ";
const char PROGMEM Waiting2[] = " mSec sample at ";
const char PROGMEM Waiting3[] = " uSec sample rate";

void
help(void) {
  Serial.println(fstr(Digital_oscope));
  Serial.println(fstr(F_command));
  Serial.println(fstr(S_command));
  Serial.println(fstr(C_command));
}

void
setup(void) {
  Serial.begin(57600);

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
  
  // Set up timer 2 prescaler to 8, so timer ticks at .5 uSec.
  //TIMSK0 = 0;     // disable interrupts
  //TCCR2A = 0;     // WGM = 0 (normal mode)
  //TCCR2B = 0x02;  // prescaler: timer clk == cpu clk / 8
  //ASSR = 0;
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
get_slow_data(int sample_rate) {
  byte b1 = 0, b2;
  while (!((b2 = PINB) & 1)) b1 = b2;
  unsigned long start_time = micros();
  Data[0] = b1;
  Data[1] = b2;
  unsigned long target_time = 0;
  for (int i = 2; i < DATA_SIZE; i++) {
    target_time += sample_rate;
    while (micros() - start_time < target_time) ;
    Data[i] = PINB;
  }
}

void
get_changes(void) {
  /*******
  This records two bytes per sample:
    1.  time since last sample (in .01 mSec increments).
    2.  the sample
  Initial 255 values add to the length and to the time since the last sample.
  It is possible that the 255 prefixes exhaust the Data buffer.  In this case
  the last buffer value is unset.
  The first two bytes are the pre-trigger and trigger values.  No times are
  stored for these.
  ********/
  byte b1 = 0, b2;
  while (!((b2 = PINB) & 1)) b1 = b2;
  unsigned long last_time = micros();
  Data[0] = b1;
  Data[1] = b2;
  for (int i = 2; i < DATA_SIZE - 1; i += 2) {
    unsigned long now;
    for (;;) {
      now = micros();
      if ((b1 = PINB) != b2) break;
      if (now - last_time >= 2550ul) {
        Data[i++] = 255;
        if (i >= DATA_SIZE - 1) {
          // not enough room for 2 more bytes...
          return;
        }
        last_time += 2550;
      }
    }
    unsigned int elapsed = (unsigned int)((now - last_time) / 10);
    while (elapsed > 254) {
      Data[i++] = 255;
      elapsed -= 255;
      if (i >= DATA_SIZE - 1) return;
    }
    Data[i] = byte(elapsed);
    Data[i + 1] = b1;
    b2 = b1;
    last_time = now;
  }
}

unsigned long
send_bits(byte last, byte now,
          unsigned long delta_time, unsigned long cumulative_time)
{
  for (byte i = 0; i < 6; i++) {
    byte bit = 1 << i;
    if ((last & bit) == (now & bit)) Serial.print(". ");
    else if (now & bit) Serial.print("+ ");
    else Serial.print("- ");
  }
  Serial.print(delta_time);
  cumulative_time += delta_time;
  Serial.print(' ');
  Serial.println(cumulative_time);
  return cumulative_time;
}

void
send_changes(void) {
  for (byte j = 0; j < 6; j++) {
    if (Data[0] & (1 << j)) {
      Serial.print("+ ");
    } else {
      Serial.print("- ");
    }
  }
  Serial.println(fstr(Pre_trigger));
  byte last_byte = Data[0];
  unsigned long cumulative_time = send_bits(last_byte, Data[1], 0ul, 0ul);
  for (int i = 2; i < DATA_SIZE - 1; i += 2) {
    unsigned long delta_time = 0;
    while (Data[i] == 255) {
      delta_time += 2550;
      if (++i >= DATA_SIZE - 1) return;
    }
    delta_time += Data[i] * 10;
    cumulative_time = send_bits(last_byte, Data[i + 1], delta_time,
                                cumulative_time);
    last_byte = Data[i + 1];
  }
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
  Serial.println(fstr(Pre_trigger));
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
      Serial.print(' ');
      Serial.println(i * sample_rate);
      last = i;
    }
  }
}

int
get_num(void) {
  int ans = 0;
  for (;;) {
    while (Serial.available() == 0) ;
    byte c = Serial.read();
    if (isdigit(c)) ans = 10*ans + c - '0';
    else if (c == '.') return ans;
    else return -1;
  }
}


void
loop(void) {
  if (Serial.available()) {
    int i;
    byte c = Serial.read();
    switch (c) {
    case 'c':
      Serial.println(fstr(Waiting_750_changes));
      get_changes();
      send_changes();
      break;
    case 'f':
      Serial.println(fstr(Waiting_fast));
      get_data();
      send_data(3.0/16.0);
      break;
    case 's':
      i = get_num();
      if (i < 0) help();
      else {
        int msec = i + i/2;
        Serial.print(fstr(Waiting1));
        Serial.print(msec);
        Serial.print(fstr(Waiting2));
        Serial.print(i);
        Serial.println(fstr(Waiting3));
        get_slow_data(i);
        send_data(float(i));
      }
      break;
    default:
      help();
      break;
    }
  }
}
