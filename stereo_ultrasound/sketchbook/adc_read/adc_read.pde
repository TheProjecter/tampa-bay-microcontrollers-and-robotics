// adc_read.pde

#include <avr/pgmspace.h>


#define DIST_BETWEEN_SENSORS    (2*1200)        /* hundredths of an inch */

/************************* M1300 Pins ******************************
 *
 *  Pin 1 (green): open (high) -> serial output on pin 5,
 *                 low -> pin 5 sends pulse suitable for low noise chaining.
 *  Pin 2 (red):   analog envelope output
 *  Pin 3 (black): analog voltage with scaling factor of Vcc/1024 per cm.
 *                 (max range ~700cm at 5V).
 *  Pin 4 (white): open (high) -> continually range (hold high >= 20uSec for
 *                                range reading)
 *                         low -> stop ranging
 *  Pin 5 (green): when pin 1 is high -> serial output "Rddd\r": 9600 N-8-1,
 *                                       ddd in cm up to 765
 *                 when pin 1 is low  -> single pulse suitable for chaining
 *                                       chain to pin 4 on next unit, triggers
 *                                       next unit after this one is done.
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

// Distance == SPEED_OF_SOUND * (time + C)

// in/sec
#define SPEED_OF_SOUND          (float(1133.34)*12.0)

// Time offset (uSec)
#define C                       -354

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

const prog_char Oops[] PROGMEM = "oops!\n";
const prog_char Min[] PROGMEM = "min ";
const prog_char Max[] PROGMEM = "max ";
const prog_char Stars[] PROGMEM = "*************************\n";
const prog_char Continue[] PROGMEM = "hit ENTER to continue\n";
const prog_char Help1[] PROGMEM = "help:\n";
const prog_char Help2[] PROGMEM = "  h     help\n";
const prog_char Help3[] PROGMEM = "  -     no ping\n";
const prog_char Help4[] PROGMEM = "  r     ping right\n";
const prog_char Help5[] PROGMEM = "  R     ping right, report peaks\n";
const prog_char Help6[] PROGMEM = "  L     ping left, report peaks\n";
const prog_char Help7[] PROGMEM = "  else  ping left\n\n";
const prog_char Left_pin[] PROGMEM = "LEFT_PING_PIN is ";
const prog_char Right_pin[] PROGMEM = "RIGHT_PING_PIN is ";
const prog_char High[] PROGMEM = "HIGH\n";
const prog_char Low[] PROGMEM = "LOW\n";

void
print_P(const char PROGMEM *s) {
    for (byte b = pgm_read_byte(s++); b; b = pgm_read_byte(s++)) {
        Serial.print(b, BYTE);
    }
}

void
help(void) {
    print_P(Help1);
    print_P(Help2);
    print_P(Help3);
    print_P(Help4);
    print_P(Help5);
    print_P(Help6);
    print_P(Help7);

    print_P(Left_pin);
    if (digitalRead(LEFT_PING_PIN)) {
        print_P(High);
    } else {
        print_P(Low);
    }

    print_P(Right_pin);
    if (digitalRead(RIGHT_PING_PIN)) {
        print_P(High);
    } else {
        print_P(Low);
    }
}

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

    help();

    delay(250);                     // give units time to initialize
}

// Samples/Times/Num_peaks[0] is left, Samples/Times/Num_peaks[1] is right
int Samples[2][NUM_SAMPLES];
unsigned int Times[2][NUM_SAMPLES];
int Num_peaks[2];
int Max_sample;
int Min_sample;

unsigned long Start;

// Pings and returns the start time of the ping in microseconds.
unsigned long
ping(byte ping_pin = LEFT_PING_PIN, byte sample_pin = LEFT_SAMPLE_PIN) {
    // trigger ping:
    digitalWrite(ping_pin, HIGH);
    delayMicroseconds(20);
    digitalWrite(ping_pin, LOW);

    // It takes 20.5 mSec before the ping is sent...
    // Wait for ping:
    int last_sample = 0;
    unsigned long last_time = 0;
    unsigned long start = micros();
    int current_sample = analogRead(sample_pin);
    while (current_sample < PING_THRESHOLD) {
        last_sample = current_sample;
        last_time = start;
        start = micros();
        current_sample = analogRead(sample_pin);
    }

    // Adjust start time:
    int d = current_sample - last_sample;
    return start
         + ((start - last_time) * (PING_THRESHOLD - last_sample) + d/2) / d;
}

// Reads NUM_SAMPLES ADC samples for both L and R sensors into Samples and
// Times arrays.  Times is microseconds.
void
read_samples(unsigned long start) {
    // Read samples:
    for (int i = 0; i < NUM_SAMPLES; i++) {
        Times[0][i] = (unsigned int)(micros() - start);
        Samples[0][i] = analogRead(LEFT_SAMPLE_PIN);
        Times[1][i] = (unsigned int)(micros() - start);
        Samples[1][i] = analogRead(RIGHT_SAMPLE_PIN);
    }
}

// Find peaks in Samples, and records them in Samples and Times overwriting
// sample data.
//   Times becomes round trip distance in hundreths of an inch.
//   Samples becomes the peak signal strength.
// This sets Num_peaks.
void
find_peaks(int low_threshold) {
    Num_peaks[0] = Num_peaks[1] = 0;

    Max_sample = 0;
    Min_sample = 15000;

    for (int i = 1; i < NUM_SAMPLES - 1; i++) {
        for (byte j = 0; j < 2; j++) {
            if (Samples[j][i] < Min_sample) {
                Min_sample = Samples[j][i];
            }
            if (Samples[j][i] > Max_sample) {
                Max_sample = Samples[j][i];
            }
            if (Samples[j][i] > low_threshold &&
                Samples[j][i] > Samples[j][i - 1] &&
                Samples[j][i] > Samples[j][i + 1]
            ) {
                // t1 is i-1, t2 is i and t3 is i+1

                // we take Times[j][i] as 0 to give us c directly:
                float c = Samples[j][i];        // at t2

                float t1 = -float(Times[j][i] - Times[j][i-1]);
                float t3 = Times[j][i+1] - Times[j][i];

                // equation1: a * a1 + b * b1 + c1 == 0
                float a1 = t1*t1;
                float b1 = t1;
                float c1 = c - Samples[j][i-1];

                // equation3: a * a3 + b * b3 + c3 == 0
                float a3 = t3*t3;
                float b3 = t3;
                float c3 = c - Samples[j][i+1];

                // multiply equation1 * (a3/a1) and subtract equation3 to get
                // equation4: b*b4 + c4 == 0
                float b4 = b1 * (a3/a1) - b3;
                float c4 = c1 * (a3/a1) - c3;

                // solve equation4 for b:
                float b = -c4/b4;

                // solve equation1 for a:
                float a = -(b1*b + c1)/a1;

                if (a >= 0.0) {
                    print_P(Oops);
                } else {
                    float t_max = -b/(2.0*a);
                    float s_max = a*t_max*t_max + b*t_max + c;
                    t_max += Times[j][i];
                    float d_max = SPEED_OF_SOUND / 1e6 * float(t_max + C);
                    Samples[j][Num_peaks[j]] = int(s_max);
                    Times[j][Num_peaks[j]] = (unsigned int)(d_max * 100);
                    Num_peaks[j] += 1;
                }
            } // end if (max)
        } // end for (j)
    } // end for (i)
}

void
report_peak(char side, int sample, unsigned int round_trip_distance) {
    Serial.print(side);
    Serial.print(": ");
    Serial.print(sample);
    Serial.print('@');
    Serial.println(float(round_trip_distance)/200.0);
}

// Report peaks that are stored in Samples and Times.
void
report_peaks(void) {
    int i[2];
    i[0] = i[1] = 0;

    for (;;) {
        if (i[0] < Num_peaks[0]) {      // there are more left peaks
            if (i[1] < Num_peaks[1] && Times[1][i[1]] < Times[0][i[0]]) {
                report_peak('R', Samples[1][i[1]], Times[1][i[1]]);
                i[1] += 1;
            } else {
                report_peak('L', Samples[0][i[0]], Times[0][i[0]]);
                i[0] += 1;
            }
        } else if (i[1] < Num_peaks[1]) {
            report_peak('R', Samples[1][i[1]], Times[1][i[1]]);
            i[1] += 1;
        } else break;
    } // end for (;;)

    print_P(Min);
    Serial.println(Min_sample);
    print_P(Max);
    Serial.println(Max_sample);
}

void
report_object(int peak_sample, unsigned int distance, int angle) {
    Serial.print(float(distance)/200.0);
    Serial.print('@');
    Serial.print(angle);
    Serial.print('=');
    Serial.println(peak_sample);
}

int
calc_angle(unsigned int dist_left, unsigned int dist_right, byte ping_left) {
    /***********************************************************************
     *
     *                 .|
     *               . .|
     *             .  . |
     *           .   .  |
     *         .    .   |
     *     dl.   dr.    | y
     *     .      .     |
     *   ^-------^------+
     *   |<--d-->|
     *   |<------x----->|
     *
     * For above example (x > d > 0):
     *    x**2 + y**2 == dl**2
     *    (x-d)**2 + y**2 == dr**2
     *
     * For in-between case (d > x > 0):
     *    x**2 + y**2 == dl**2
     *    (d-x)**2 + y**2 == dr**2
     *
     * For x < 0 case:
     *    x**2 + y**2 == dl**2
     *    (x+d)**2 + y**2 == dr**2
     *
     *    dl**2 - x**2 == dr**2 - (x**2 +/- 2dx + d**2)
     *    dr**2 - (x**2 +/- 2dx + d**2) == dl**2 - x**2
     *    -/+ 2dx - d**2 == dl**2 - dr**2
     *    x == -/+(dl**2 - dr**2 + d**2) / (2d)
     *
     *    y == sqrt(dl**2 - x**2)
     *
     ***********************************************************************/

    if (ping_left) {
        dist_left /= 2;
        dist_right -= dist_left;
    } else {
        dist_right /= 2;
        dist_left -= dist_right;
    }
    unsigned long dl2 = (unsigned long)dist_left * (unsigned long)dist_left;
    unsigned long dr2 = (unsigned long)dist_right * (unsigned long)dist_right;
    unsigned long d = (unsigned long)DIST_BETWEEN_SENSORS;
    unsigned long d2 = d * d;
    int x = (dl2 - dr2 + d2) / (2*d);
    if (dr2 - d2 > dl2) x = -x;
    int y = sqrt(dl2 - x*x);
    return 180.0 * atan2(y, x) / M_PI - 90.0;
}

void
find_objects(byte ping_left) {
    int i[2];
    i[0] = i[1] = 0;

    while (i[0] < Num_peaks[0] && i[1] < Num_peaks[1]) {
        unsigned int dist_left = Times[0][i[0]];
        unsigned int dist_right = Times[1][i[1]];
        if (dist_left <= dist_right) {
            if (dist_right - dist_left <= DIST_BETWEEN_SENSORS) {
                report_object(max(Samples[0][i[0]], Samples[1][i[1]]),
                              ping_left ? dist_left : dist_right,
                              calc_angle(dist_left, dist_right, ping_left));
                i[1] += 1;
            } else {
                report_object(Samples[0][i[0]], dist_left, 90);
            }
            i[0] += 1;
        } else { // dist_left > dist_right
            if (dist_left - dist_right <= DIST_BETWEEN_SENSORS) {
                report_object(max(Samples[0][i[0]], Samples[1][i[1]]),
                              ping_left ? dist_left : dist_right,
                              calc_angle(dist_left, dist_right, ping_left));
                i[0] += 1;
            } else {
                report_object(Samples[1][i[1]], dist_right, -90);
            }
            i[1] += 1;
        }
    } // end while (i[0] < Num_peaks[0] && i[1] < Num_peaks[1])

    if (i[0] < Num_peaks[0]) {
        report_object(Samples[0][i[0]], Times[0][i[0]], 90);
    }
    if (i[1] < Num_peaks[1]) {
        report_object(Samples[1][i[1]], Times[1][i[1]], -90);
    }
}

void
loop(void) {
    while (!Serial.available()) ;
    char c = Serial.read();
    Serial.flush();     // purge input data
    print_P(Stars);
    byte ping_left;
    byte do_report_peaks = 0;
    switch (c) {
    case 'h':
        help();
        return;
    case '-':
        read_samples(micros());
        find_peaks(0);
        report_peaks();
        return;
    case 'r':
        read_samples(ping(RIGHT_PING_PIN, RIGHT_SAMPLE_PIN));
        find_peaks(LOW_THRESHOLD);
        ping_left = 0;
        break;
    case 'R':
        read_samples(ping(RIGHT_PING_PIN, RIGHT_SAMPLE_PIN));
        find_peaks(LOW_THRESHOLD);
        ping_left = 0;
        do_report_peaks = 1;
        break;
    case 'L':
        read_samples(ping(LEFT_PING_PIN, LEFT_SAMPLE_PIN));
        find_peaks(LOW_THRESHOLD);
        ping_left = 1;
        do_report_peaks = 1;
        break;
    default:
        read_samples(ping(LEFT_PING_PIN, LEFT_SAMPLE_PIN));
        find_peaks(LOW_THRESHOLD);
        ping_left = 1;
        break;
    } // end switch (c)
    if (do_report_peaks) {
        report_peaks();
        print_P(Continue);
        while (!Serial.available()) ;
        Serial.flush();     // purge input data
    }
    find_objects(ping_left);
}
