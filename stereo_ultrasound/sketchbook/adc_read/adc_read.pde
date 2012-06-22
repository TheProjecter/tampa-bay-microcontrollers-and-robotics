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
 *                                       to pin 4 on next unit, triggers next
 *                                       unit after this one is done.
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
//#define SPEED_OF_SOUND          (float(1133.34)*12.0)
#define SPEED_OF_SOUND          (float(1176.29)*12.0)

// Time offset (uSec)
#define C                       -1130

#define inches(time)            (SPEED_OF_SOUND / 1e6 * float(time + C))

// We sample at about 5 samples/ft (round trip), so 40*5 is up to 40ft round
// trip, or 20ft away.
// This requires 8 bytes per sample.
#define NUM_SAMPLES                     (40*5)
//#define NUM_SAMPLES                     (20*5)

#define LEFT_SAMPLE_PIN                 0
#define RIGHT_SAMPLE_PIN                1

#define LEFT_SAMPLE_PIN_DIGITAL         A0
#define RIGHT_SAMPLE_PIN_DIGITAL        A1

#define LEFT_PING_PIN                   3
#define RIGHT_PING_PIN                  5

#define PING_THRESHOLD                  630
#define LOW_THRESHOLD                   230

//#define SCORE_THRESHOLD                 1.8
#define SCORE_THRESHOLD                 1.5

const prog_char Oops[] PROGMEM = "print oops!\n";
const prog_char Min[] PROGMEM = "print min ";
const prog_char Max[] PROGMEM = "print max ";
const prog_char Stars[] PROGMEM = "print *************************\n";
const prog_char Continue[] PROGMEM = "print hit ENTER to continue\n";
const prog_char Help1[] PROGMEM  = "print help:\n";
const prog_char Help2[] PROGMEM  = "print   h     help\n";
const prog_char Help3[] PROGMEM  = "print   -     sample: no ping\n";
const prog_char Help4[] PROGMEM  = "print   l     sample: ping left\n";
const prog_char Help5[] PROGMEM  = "print   r     sample: ping right\n";
const prog_char Help6[] PROGMEM  = "print   T     plot_sample_usecs\n";
const prog_char Help7[] PROGMEM  = "print   I     plot_sample_inches\n";
const prog_char Help8[] PROGMEM  = "print   0     find_peaks(0)\n";
const prog_char Help9[] PROGMEM  = "print   p     find_peaks(LOW_THRESHOLD)\n";
const prog_char Help10[] PROGMEM = "print   P     plot_peaks\n";
const prog_char Help11[] PROGMEM = "print   f     find_objects\n";
const prog_char Left_pin[] PROGMEM = "print LEFT_PING_PIN is ";
const prog_char Right_pin[] PROGMEM = "print RIGHT_PING_PIN is ";
const prog_char High[] PROGMEM = "HIGH\n";
const prog_char Low[] PROGMEM = "LOW\n";
const prog_char Left_samples_usec[] PROGMEM = 
  "$left_samples_usec_x $left_samples_usec_y\n";
const prog_char Right_samples_usec[] PROGMEM = 
  "$right_samples_usec_x $right_samples_usec_y\n";
const prog_char Left_samples_in[] PROGMEM =
  "$left_samples_in_x $left_samples_in_y\n";
const prog_char Right_samples_in[] PROGMEM = 
  "$right_samples_in_x $right_samples_in_y\n";
const prog_char Left_peaks[] PROGMEM = "$left_peaks_x $left_peaks_y\n";
const prog_char Right_peaks[] PROGMEM = "$right_peaks_x $right_peaks_y\n";
const prog_char Print[] PROGMEM = "print ";
const prog_char Println[] PROGMEM = "print\n";
const prog_char Load[] PROGMEM = "load ";
const prog_char Plot_left_samples_usec[] PROGMEM =
  "plot $left_samples_usec_x $left_samples_usec_y g-\n";
const prog_char Plot_right_samples_usec[] PROGMEM =
  "plot $right_samples_usec_x $right_samples_usec_y r-\n";
const prog_char Plot_left_samples_in[] PROGMEM =
  "plot $left_samples_in_x $left_samples_in_y g-\n";
const prog_char Plot_right_samples_in[] PROGMEM =
  "plot $right_samples_in_x $right_samples_in_y r-\n";
const prog_char Plot_left_peaks[] PROGMEM =
  "plot $left_peaks_x $left_peaks_y g+\n";
const prog_char Plot_right_peaks[] PROGMEM =
  "plot $right_peaks_x $right_peaks_y r+\n";
const prog_char Show[] PROGMEM = "show\n";
const prog_char Get_command[] PROGMEM = "input (h|-|l|r|T|I|0|p|P|f)?\n";
const prog_char Unknown_command[] PROGMEM = "print unknown command\n";
const prog_char Load_peaks[] PROGMEM = "load $peak_x $peak_y\n";
const prog_char Plot_peaks[] PROGMEM = "plot $peak_x $peak_y b-\n";
const prog_char Plot[] PROGMEM = "plot ";
const prog_char Single_peak[] PROGMEM = " bD\n";
const prog_char Point[] PROGMEM = " b*\n";

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
    print_P(Help8);
    print_P(Help9);
    print_P(Help10);
    print_P(Help11);
    print_P(Println);

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

// uSecs (up to 65mSec, or ~32ft round trip) for samples
// inches * 100 for peaks
unsigned int Times[2][NUM_SAMPLES];

int Num_peaks[2];
int Max_sample;
int Min_sample;
byte First[2];          // skips over times < -C

unsigned long Start;    // ping time in uSecs

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

    // Adjust start time to est PING_THRESHOLD crossing time:
    int d = current_sample - last_sample;
    return last_time
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
    if (C < 0) {
        for (byte left_right = 0; left_right < 2; left_right++) {
            for (int i = 0; i < NUM_SAMPLES; i++) {
                if (Times[left_right][i] >= -C) {
                    First[left_right] = i;
                    break;
                }
            }
        }
    }
}

// Loads NUM_SAMPLES ADC samples for both L and R sensors into
// Left/Right_samples_usec arrays.  Times is microseconds.
void
load_sample_usecs(void) {
    // Dump samples:
    for (byte i = 0; i < 2; i++) {
        print_P(Load);
        //Serial.print(NUM_SAMPLES);
        //Serial.print(' ', BYTE);
        if (i == 0) print_P(Left_samples_usec);
        else print_P(Right_samples_usec);
        for (int j = 0; j < NUM_SAMPLES; j++) {
            Serial.print(Times[i][j]);
            Serial.print(' ', BYTE);
            Serial.println(Samples[i][j]);
        } // end for (j)
        Serial.print('\n', BYTE);    // signal end of data
    } // end for (i)
}

void
plot_sample_usecs(void) {
    print_P(Plot_left_samples_usec);
    print_P(Plot_right_samples_usec);
    //print_P(Show);
}

// Loads NUM_SAMPLES ADC samples for both L and R sensors into
// Left/Right_samples_in arrays.  Distance is inches/2.
void
load_sample_inches(void) {
    // Dump samples:
    for (byte i = 0; i < 2; i++) {
        print_P(Load);
        //Serial.print(NUM_SAMPLES);
        //Serial.print(' ', BYTE);
        if (i == 0) print_P(Left_samples_in);
        else print_P(Right_samples_in);
        for (int j = First[i]; j < NUM_SAMPLES; j++) {
            Serial.print(inches(Times[i][j])/2.0);
            Serial.print(' ', BYTE);
            Serial.println(Samples[i][j]);
        } // end for (j)
        Serial.print('\n', BYTE);    // signal end of data
    } // end for (i)
}

void
plot_sample_inches(void) {
    print_P(Plot_left_samples_in);
    print_P(Plot_right_samples_in);
    //print_P(Show);
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

    for (byte j = 0; j < 2; j++) {
        for (int i = First[j]+1; i < NUM_SAMPLES - 1; i++) {
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
                    float d_max = inches(t_max);
                    Samples[j][Num_peaks[j]] = int(s_max);
                    Times[j][Num_peaks[j]] = (unsigned int)(d_max * 100);
                    Num_peaks[j] += 1;
                }
            } // end if (max)
        } // end for (i)
    } // end for (j)
}

void
load_peak(int sample, unsigned int round_trip_distance) {
    Serial.print(float(round_trip_distance)/200.0);
    Serial.print(' ', BYTE);
    Serial.println(sample);
}

// Load peaks that are stored in Samples and Times.
void
load_peaks(void) {
    for (byte i = 0; i < 2; i++) {
        print_P(Load);
        //Serial.print(Num_peaks[i]);
        //Serial.print(' ', BYTE);
        if (i == 0) print_P(Left_peaks);
        else print_P(Right_peaks);
        for (int j = 0; j < Num_peaks[i]; j++) {
            load_peak(Samples[i][j], Times[i][j]);
        } // end for (j)
        Serial.print('\n', BYTE);
    } // end for (i)

    print_P(Min);
    Serial.println(Min_sample);
    print_P(Max);
    Serial.println(Max_sample);
}

// Plot peaks that are stored in Left/Right_peaks against Left/Right_samples_in.
void
plot_peaks(void) {
    print_P(Plot_left_samples_in);
    print_P(Plot_right_samples_in);
    print_P(Plot_left_peaks);
    print_P(Plot_right_peaks);
    //print_P(Show);
}

void
report_object(int ping_side, int ping_index, int idle_index, int peak_sample,
              int x, int y)
{
    // ping_index or idle_index is -1 if not matched.
    print_P(Print);
    Serial.print(peak_sample);
    Serial.print('@');
    Serial.print(float(x)/100.0);
    Serial.print(',');
    Serial.println(float(y)/100.0);

    // plot the peaks
    int idle_side = 1 - ping_side;
    if (ping_index >= 0 && idle_index >= 0) {
        print_P(Load_peaks);
        Serial.print(float(Times[ping_side][ping_index])/200.0);
        Serial.print(' ');
        Serial.println(Samples[ping_side][ping_index]);
        Serial.print(float(Times[idle_side][idle_index])/200.0);
        Serial.print(' ');
        Serial.println(Samples[idle_side][idle_index]);
        Serial.print('\n', BYTE);
        print_P(Plot_peaks);
    } else {
        print_P(Plot);
        if (ping_index >= 0) {
            Serial.print(float(Times[ping_side][ping_index])/200.0);
            Serial.print(' ');
            Serial.print(Samples[ping_side][ping_index]);
        } else {
            Serial.print(float(Times[idle_side][idle_index])/200.0);
            Serial.print(' ');
            Serial.print(Samples[idle_side][idle_index]);
        }
        print_P(Single_peak);
    }

    // plot the position of the object:
    print_P(Plot);
    Serial.print(float(x)/100.0);
    Serial.print(' ');
    Serial.print(float(y)/100.0);
    print_P(Point);
}

void
calc_position(unsigned int dist_ping, unsigned int dist_idle, int *x, int *y) {
    /***********************************************************************
     *
     *                 .|
     *               . .|
     *             .  . |
     *           .   .  |
     *         .    .   |
     *     dp.   di.    | y
     *     .      .     |
     *   ^-------^------+
     *   |<--d-->|
     *   |<------x----->|
     *
     * For above example (x > d > 0):
     *    x**2 + y**2 == dp**2
     *    (x-d)**2 + y**2 == di**2
     *
     * For in-between case (d > x > 0):
     *    x**2 + y**2 == dp**2
     *    (d-x)**2 + y**2 == di**2
     * or (x-d)**2 + y**2 == di**2
     *
     * For x < 0 case:
     *    x**2 + y**2 == dp**2
     *    (-x+d)**2 + y**2 == di**2
     * or (d-x)**2 + y**2 == di**2
     * or (x-d)**2 + y**2 == di**2
     *
     *    dp**2 - x**2 == di**2 - (x**2 - 2dx + d**2)
     *    di**2 - (x**2 - 2dx + d**2) == dp**2 - x**2
     *    di**2 - x**2 + 2dx - d**2 == dp**2 - x**2
     *    2dx - d**2 == dp**2 - di**2
     *    x == (dp**2 - di**2 + d**2) / (2d)
     *
     *    y == sqrt(dp**2 - x**2)
     *
     ***********************************************************************/

    dist_ping /= 2;
    dist_idle -= dist_ping;
    unsigned long dp2 = (unsigned long)dist_ping * (unsigned long)dist_ping;
    unsigned long di2 = (unsigned long)dist_idle * (unsigned long)dist_idle;
    unsigned long d = (unsigned long)DIST_BETWEEN_SENSORS;
    unsigned long d2 = d * d;
    int x_tmp = (dp2 - di2 + d2) / (2*d);
    *x = x_tmp;
    *y = sqrt(dp2 - x_tmp*x_tmp);
    //return 180.0 * atan2(y, x) / M_PI - 90.0;
}

void
find_objects(byte ping_side) {
    byte i[2];
    byte idle_side = 1 - ping_side;

    byte first_idle = 0;

    // get idle side past direct sense of ping
    while (first_idle < Num_peaks[idle_side]
        && Times[idle_side][first_idle] < 50
    ) {
        first_idle += 1;
    }

    // zero out end of Samples[idle_side] to track which idle_side peaks we've
    // matched.
    for (i[idle_side] = first_idle;
         i[idle_side] < Num_peaks[idle_side];
         i[idle_side]++
    ) {
        Samples[idle_side][NUM_SAMPLES - 1 - i[idle_side]] = 0;
    }

    for (i[ping_side] = 0;
         i[ping_side] < Num_peaks[ping_side];
         i[ping_side]++
    ) {
        byte best_fit = 0;
        float best_score = 1e10;
        unsigned int time_ping = Times[ping_side][i[ping_side]];
        float dist_ping = time_ping / 2.0;
        float ping_wammy = dist_ping*dist_ping*Samples[ping_side][i[ping_side]];

        for (i[idle_side] = first_idle;
             i[idle_side] < Num_peaks[idle_side];
             i[idle_side]++
        ) {
            unsigned int time_idle = Times[idle_side][i[idle_side]];
            if (time_idle < time_ping
                && time_ping - time_idle > DIST_BETWEEN_SENSORS
            ) {
                continue;
            }
            if (time_idle > time_ping
                && time_idle - time_ping > DIST_BETWEEN_SENSORS
            ) {
                break;
            }

            float dist_idle = time_idle - dist_ping;
            float idle_wammy = 
              dist_idle*dist_idle*Samples[idle_side][i[idle_side]];
            float score = ping_wammy >= idle_wammy
                          ? ping_wammy / idle_wammy
                          : idle_wammy / ping_wammy;
            if (score <= SCORE_THRESHOLD && score < best_score) {
                best_score = score;
                best_fit = i[idle_side];
            }
        } // end for (i[idle_side])

        if (best_fit == 0) {
            /*****
            report_object(ping_side, i[ping_side], -1,
                          Samples[ping_side][i[ping_side]],
                          ping_side ? time_ping/2 : -time_ping/2, 0);
             *****/
        } else {
            int x, y;
            calc_position(time_ping, Times[idle_side][best_fit], &x, &y);
            report_object(ping_side, i[ping_side], best_fit,
                          max(Samples[ping_side][i[ping_side]],
                              Samples[idle_side][best_fit]),
                          x, y);
            Samples[idle_side][NUM_SAMPLES - 1 - best_fit] = 1;
        }
    } // end for (i[ping_side])

    /************
    // report any unmatched peaks on the idle_side
    for (i[idle_side] = first_idle;
         i[idle_side] < Num_peaks[idle_side];
         i[idle_side]++
    ) {
        if (Samples[idle_side][NUM_SAMPLES - 1 - i[idle_side]] == 0) {
            int time_idle = Times[idle_side][i[idle_side]]
                            + DIST_BETWEEN_SENSORS;
            report_object(ping_side, -1, i[idle_side],
                          Samples[idle_side][i[idle_side]],
                          ping_side ? -time_idle/2 : time_idle/2, 0);
        }
    }
     ************/
    plot_peaks();
    print_P(Show);
}

byte Ping_side;

void
loop(void) {
    Serial.flush();     // purge input data
    print_P(Get_command);
    while (!Serial.available()) ;
    char c = Serial.read();
    print_P(Stars);
    switch (c) {
    case 'h':
        help();
        break;
    case '-':
        read_samples(micros());
        break;
    case 'l':
        read_samples(ping(LEFT_PING_PIN, LEFT_SAMPLE_PIN));
        Ping_side = 0;
        load_sample_usecs();
        load_sample_inches();
        break;
    case 'r':
        read_samples(ping(RIGHT_PING_PIN, RIGHT_SAMPLE_PIN));
        Ping_side = 1;
        break;
    case 'T':
        plot_sample_usecs();
        print_P(Show);
        break;
    case 'I':
        plot_sample_inches();
        print_P(Show);
        break;
    case '0':
        find_peaks(0);
        load_peaks();
        break;
    case 'p':
        find_peaks(LOW_THRESHOLD);
        load_peaks();
        break;
    case 'P':
        plot_peaks();
        break;
    case 'f':
        find_objects(Ping_side);
        break;
    default:
        print_P(Unknown_command);
        break;
    } // end switch (c)
}
