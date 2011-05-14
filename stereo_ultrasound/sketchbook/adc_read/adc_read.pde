// adc_read.pde


/************************* M1300 Pins ******************************
 *
 *  Pin 1: open (high) -> serial output on pin 5,
 *         low -> pin 5 sends pulse suitable for low noise chaining.
 *  Pin 2: analog envelope output
 *  Pin 3: analog voltage with scaling factor of Vcc/1024 per cm.
 *         (max range ~700cm at 5V).
 *  Pin 4: open (high) -> continually range (hold high >= 20uSec for range
 *                        reading)
 *         low -> stop ranging
 *  Pin 5: when pin 1 is high -> serial output "Rddd\r": 9600 N-8-1, ddd in cm
 *                               up to 765
 *         when pin 1 is low  -> single pulse suitable for chaining
 *                               chain to pin 4 on next unit, triggers next
 *                               unit after this one is done.
 *
 *******************************************************************/

/****************** We want ********************
 *
 * Pin 1: N/C
 * Pin 2: connected to ADC sample input pin
 * Pin 3: N/C
 * Pin 4: connected to PING pin
 * Pin 5: N/C
 *
 ***********************************************/

/**************** OBSERVATIONS *****************
 *
 * No signal is ~1V.
 *
 * Initial ping goes just over 3V, then slightly down for .3 mSec, then
 * rounded up to 3.5-3.6V at 1 mSec.
 *
 * Looks like you can look at either initial climb or peak.
 *
 * 2.25" off floor to sensor.
 * 34.25" table top == 5.3 mSec round trip (oscope), 69.76  69.92  70.40  69.78
 * 98.25" ceiling == 14.8 mSec round trip (oscope), 199.80 199.98 200.82 199.24
 *                                     differences: 130.04 130.06 130.42 129.46
 *
 * From oscope:
 *
 *   m*14.8 + c == 192"
 * - m*5.3 + c  == 64"
 * ----------------------
 *   m*9.5      == 128
 *
 * m = 13.47 in/mSec (1122.5 ft/sec)
 * c = -7.391 -7.356 (mSec)
 *
 * From program:
 *
 * m = 0.98466 (speed of sound should be 1133.34 ft/sec)
 * c = -4.89123 (going to depend on start pulse timing) (== -0.354 mSec)
 *
 ***********************************************/

// in/sec
#define SPEED_OF_SOUND          float(1151*12)

// This requires 4 bytes per sample.
#define NUM_SAMPLES                     40*5
//#define NUM_SAMPLES                     20*5

#define LEFT_SAMPLE_PIN                 0
#define RIGHT_SAMPLE_PIN                1

#define LEFT_SAMPLE_PIN_DIGITAL         A0
#define RIGHT_SAMPLE_PIN_DIGITAL        A1

#define LEFT_PING_PIN                   3
#define RIGHT_PING_PIN                  5

#define PING_THRESHOLD                  630
#define LOW_THRESHOLD                   230

void
setup(void) {
    pinMode(LEFT_SAMPLE_PIN_DIGITAL, INPUT);
    pinMode(RIGHT_SAMPLE_PIN_DIGITAL, INPUT);
    digitalWrite(LEFT_SAMPLE_PIN_DIGITAL, LOW);         // disable pullups
    digitalWrite(RIGHT_SAMPLE_PIN_DIGITAL, LOW);        // disable pullups

    digitalWrite(LEFT_PING_PIN, LOW);
    digitalWrite(RIGHT_PING_PIN, LOW);
    pinMode(LEFT_PING_PIN, OUTPUT);
    pinMode(RIGHT_PING_PIN, OUTPUT);

    Serial.begin(57600);

    delay(250);                     // give units time to initialize
}

int Samples[2][NUM_SAMPLES];        // Samples[0] is left, Samples[1] is right
unsigned int Time[2][NUM_SAMPLES];

void
ping(void) {
    int i;

    // trigger ping:
    digitalWrite(LEFT_PING_PIN, HIGH);
    //digitalWrite(RIGHT_PING_PIN, HIGH);
    delayMicroseconds(20);
    //delayMicroseconds(400);
    digitalWrite(LEFT_PING_PIN, LOW);
    //digitalWrite(RIGHT_PING_PIN, LOW);

    // It takes 20.5 mSec before the ping is sent...
    // Wait for ping:
    while (analogRead(LEFT_SAMPLE_PIN) < PING_THRESHOLD) ;

    // It's show time!
    unsigned long start = micros();

    // read samples:
    for (i = 0; i < NUM_SAMPLES; i++) {
        Time[0][i] = (unsigned int)(micros() - start);
        Samples[0][i] = analogRead(LEFT_SAMPLE_PIN);
        Time[1][i] = (unsigned int)(micros() - start);
        Samples[1][i] = analogRead(RIGHT_SAMPLE_PIN);
    }

    // report results:
    for (i = 1; i < NUM_SAMPLES - 1; i++) {
        for (byte j = 0; j < 2; j++) {
            if (Samples[j][i] > LOW_THRESHOLD &&
                Samples[j][i] > Samples[j][i - 1] &&
                Samples[j][i] > Samples[j][i + 1]
            ) {
                /**************************
                Serial.print('\n');

                Serial.print(j, DEC);
                Serial.print(':');
                Serial.print(Samples[j][i-1]);
                Serial.print(' ');
                Serial.print(Samples[j][i]);
                Serial.print(' ');
                Serial.print(Samples[j][i+1]);
                Serial.print('@');
                Serial.println(Time[j][i]);
                **************************/

                // t1 is i-1, t2 is i and t3 is i+1

                // we take Time[j][i] as 0 to give us c directly:
                float c = Samples[j][i];        // at t2

                float t1 = -float(Time[j][i] - Time[j][i-1]);
                float t3 = Time[j][i+1] - Time[j][i];

                /**************************
                Serial.print(t1);
                Serial.print('<');
                Serial.print(c);
                Serial.print('<');
                Serial.println(t3);
                **************************/

                // equation1: a * a1 + b * b1 + c1 == 0
                float a1 = t1*t1;
                float b1 = t1;
                float c1 = c - Samples[j][i-1];

                /**************************
                Serial.print("e1: ");
                Serial.print(a1);
                Serial.print(',');
                Serial.print(b1);
                Serial.print(',');
                Serial.println(c1);
                **************************/

                // equation3: a * a3 + b * b3 + c3 == 0
                float a3 = t3*t3;
                float b3 = t3;
                float c3 = c - Samples[j][i+1];

                /**************************
                Serial.print("e3: ");
                Serial.print(a3);
                Serial.print(',');
                Serial.print(b3);
                Serial.print(',');
                Serial.println(c3);
                **************************/

                // multiply equation1 * (a3/a1) and subtract equation3 to get
                // equation4: b*b4 + c4 == 0
                float b4 = b1 * (a3/a1) - b3;
                float c4 = c1 * (a3/a1) - c3;

                /**************************
                Serial.print("e4: ");
                Serial.print(b4);
                Serial.print(',');
                Serial.println(c4);
                **************************/

                // solve equation4 for b:
                float b = -c4/b4;

                // solve equation1 for a:
                float a = -(b1*b + c1)/a1;

                /**************************
                Serial.print("a=");
                Serial.print(a);
                Serial.print(", b=");
                Serial.println(b);
                **************************/

                if (a >= 0.0) {
                    Serial.println("oops!");
                } else {
                    float t_max = -b/(2.0*a);
                    float s_max = a*t_max*t_max + b*t_max + c;
                    float d_max = (t_max + Time[j][i]) / 1e6 * SPEED_OF_SOUND;
                    if (j == 0) Serial.print("L: ");
                    else        Serial.print("R: ");
                    Serial.print(s_max);
                    Serial.print("@");
                    Serial.println(d_max);
                }
            } // end if (max)
        } // end for (j)
    } // end for (i)
}

void
loop(void) {
    while (!Serial.available()) ;
    Serial.flush();     // purge input data
    Serial.println("-------");
    ping();
}
