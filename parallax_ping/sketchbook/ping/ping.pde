// ping.pde

#define PING_PIN                7

#define SPEED_OF_SOUND_FT_SEC   1155ul
#define SPEED_OF_SOUND_IN_SEC   (SPEED_OF_SOUND_FT_SEC * 12ul)

void
setup(void) {
    Serial.begin(57600);
}

void
loop(void) {
    // Send trigger pulse:
    digitalWrite(PING_PIN, LOW);
    pinMode(PING_PIN, OUTPUT);
    delayMicroseconds(100);             // give PING time to see LOW (??)
    digitalWrite(PING_PIN, HIGH);
    delayMicroseconds(4);               // HIGH pulse width
    digitalWrite(PING_PIN, LOW);
    delayMicroseconds(100);             // LOW

    // Look for response pulse:
    pinMode(PING_PIN, INPUT);
    while (!digitalRead(PING_PIN)) ;    // wait for start of pulse
    unsigned long start_time = micros();
    while (digitalRead(PING_PIN)) ;     // wait for end of pulse
    unsigned long pulse_width = micros() - start_time;

    // Now translate the pulse width into distance (in inches).
    unsigned long quarter_inches =
      SPEED_OF_SOUND_IN_SEC * 4ul * pulse_width / 1000000ul / 2ul;

    byte feet = byte(quarter_inches / (12ul * 4ul));
    byte quarters_remainder = byte(quarter_inches % (12ul * 4ul)); 
    byte inches = quarters_remainder / 4;
    byte quarters = quarters_remainder % 4;

    // Output the results through the USB:
    // 12ft 11 1/4in
    if (feet) {
        Serial.print(feet, DEC);
        Serial.print("ft");
    }
    if (inches) {
        Serial.print(' ', BYTE);
        Serial.print(inches, DEC);
    }
    switch (quarters) {
    case 0: break;
    case 1: Serial.print(" 1/4"); break;
    case 2: Serial.print(" 1/2"); break;
    case 3: Serial.print(" 3/4"); break;
    }
    if (inches || quarters) {
        Serial.println("in");
    } else {
        Serial.println("");
    }

    // wait 500mSec between pulses.
    delay(500);
}
