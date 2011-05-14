// adc.pde

#define ADC_PIN                 1
#define ADC_PIN_DIGITAL         A1

void
setup(void) {
    pinMode(ADC_PIN_DIGITAL, INPUT);
    digitalWrite(ADC_PIN_DIGITAL, LOW); // make sure pullup is disabled...
    Serial.begin(57600);
    Serial.println("begin");
}

void
loop(void) {
    int min = 20000, max = 0;
    unsigned long start = micros();
    for (unsigned long i = 0; i < 100000; i++) {
        int adc = analogRead(ADC_PIN);
        if (adc < min) min = adc;
        if (adc > max) max = adc;
    }
    unsigned long duration = micros() - start;
    Serial.print("duration: ");
    Serial.println(duration);
    Serial.print("min: ");
    Serial.print(min);
    Serial.print(", max: ");
    Serial.println(max);
}
