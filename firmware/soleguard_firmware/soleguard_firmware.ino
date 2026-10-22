/*
 * SoleGuard - Insole Firmware (Person A)
 * ---------------------------------------------------------------
 * Target board : ESP32 (any DevKit)
 * Output       : One JSON line per reading on Serial (115200 baud),
 *                matching docs/data-contract.md EXACTLY:
 *
 * {"device_id":"INSOLE-001","user_id":"NURSE-A",
 *  "timestamp":"2026-09-24T14:32:00",
 *  "pressure":{"heel":42.5,"midfoot":18.2,"toe":30.1},
 *  "temperature_celsius":33.4,"motion_state":"standing",
 *  "battery_percent":78}
 *
 * MODE SWITCH
 *   SIMULATE_SENSORS = 1 -> fake values, no hardware needed (default)
 *   SIMULATE_SENSORS = 0 -> real FSR + DS18B20 + MPU6050
 *
 * To swap to real hardware later, ONLY change SIMULATE_SENSORS and the
 * pin numbers below. The JSON-printing code never changes, so the
 * contract stays intact.
 *
 * Libraries needed ONLY when SIMULATE_SENSORS = 0:
 *   - OneWire              (Paul Stoffregen)
 *   - DallasTemperature    (Miles Burton)
 *   - Adafruit MPU6050     (+ Adafruit Unified Sensor, Adafruit BusIO)
 */

// ===================== CONFIGURATION ============================
#define SIMULATE_SENSORS 1        // 1 = fake data, 0 = real sensors
#define PRETTY_PRINT     0        // 0 = one compact line, 1 = multi-line

const char* DEVICE_ID = "INSOLE-001";
const char* USER_ID   = "NURSE-A";

const unsigned long SAMPLE_INTERVAL_MS = 1000;   // one reading per second

// Simulated clock start (matches the contract example date)
const int START_YEAR = 2026, START_MONTH = 9, START_DAY = 24;
const int START_HOUR = 14,   START_MIN   = 32, START_SEC = 0;

// ---- Real-hardware pins (only used when SIMULATE_SENSORS = 0) ----
const int PIN_FSR_HEEL    = 34;   // ADC1 pins only (ADC2 conflicts with WiFi)
const int PIN_FSR_MIDFOOT = 35;
const int PIN_FSR_TOE     = 32;
const int PIN_DS18B20     = 4;    // OneWire data pin (4.7k pull-up to 3.3V)
const int PIN_BATTERY     = 33;   // battery voltage divider (optional)
// MPU6050 uses I2C default: SDA = GPIO21, SCL = GPIO22

// ===================== MOTION STATES ============================
// Allowed values for "motion_state". CHECK docs/data-contract.md and
// edit this list if the team's schema uses different names.
enum MotionState { SITTING, STANDING, WALKING };

// ===================== DATA STRUCTURE ===========================
// One struct holds a full reading, so the printing code is separate
// from the sensor code.
// NOTE: this must stay ABOVE every function. Arduino auto-generates
// function prototypes before the first function, and they need to
// know what "Reading" is.
struct Reading {
  float heel;
  float midfoot;
  float toe;
  float temperatureC;
  MotionState motion;
  int batteryPercent;
};

const char* motionToString(MotionState m) {
  switch (m) {
    case SITTING:  return "sitting";
    case STANDING: return "standing";
    case WALKING:  return "walking";
  }
  return "standing";
}

// ===================== REAL SENSOR SETUP ========================
#if !SIMULATE_SENSORS
  #include <OneWire.h>
  #include <DallasTemperature.h>
  #include <Wire.h>
  #include <Adafruit_MPU6050.h>
  #include <Adafruit_Sensor.h>

  OneWire oneWire(PIN_DS18B20);
  DallasTemperature tempSensor(&oneWire);
  Adafruit_MPU6050 mpu;
#endif

// ===================== SIMULATED SENSORS ========================
#if SIMULATE_SENSORS

MotionState simMotion = STANDING;
unsigned long simStateStartMs = 0;
unsigned long simStateDurationMs = 15000;   // how long to stay in a state
float simBattery = 78.0;                    // drains slowly
float simTemp = 33.4;                       // drifts slowly

// Random float in [lo, hi]
float randRange(float lo, float hi) {
  return lo + (hi - lo) * (random(0, 10001) / 10000.0f);
}

// Move between motion states every 10-30 seconds, like a real shift.
void updateSimMotion() {
  if (millis() - simStateStartMs > simStateDurationMs) {
    simMotion = (MotionState)random(0, 3);
    simStateStartMs = millis();
    simStateDurationMs = random(10000, 30000);
  }
}

// Pressure (units: whatever the team agreed on - kPa-like values here)
// depends on the motion state so the data looks realistic.
void readPressure(float &heel, float &mid, float &toe) {
  switch (simMotion) {
    case SITTING:   // little load on the foot
      heel = randRange(5, 15);  mid = randRange(2, 8);   toe = randRange(3, 10);
      break;
    case STANDING:  // steady load, heel-dominant
      heel = randRange(38, 48); mid = randRange(14, 22); toe = randRange(26, 34);
      break;
    case WALKING:   // higher, more variable load
      heel = randRange(45, 75); mid = randRange(18, 35); toe = randRange(35, 60);
      break;
  }
}

float readTemperature() {
  // Slow random walk around ~33 C, clamped to a plausible foot range.
  simTemp += randRange(-0.1, 0.1);
  if (simTemp < 31.0) simTemp = 31.0;
  if (simTemp > 36.0) simTemp = 36.0;
  return simTemp;
}

MotionState readMotion() {
  updateSimMotion();
  return simMotion;
}

int readBatteryPercent() {
  simBattery -= 0.01;                       // ~1% per 100 readings
  if (simBattery < 0) simBattery = 100;     // "recharged"
  return (int)simBattery;
}

// ===================== REAL SENSORS =============================
#else

// FSR: wired in a voltage divider -> ADC 0-4095. Convert to the unit
// the team agreed on. CALIBRATE once parts arrive (this is a placeholder
// linear scale to 0-100).
float readFsr(int pin) {
  int raw = analogRead(pin);
  return (raw / 4095.0f) * 100.0f;
}

void readPressure(float &heel, float &mid, float &toe) {
  heel = readFsr(PIN_FSR_HEEL);
  mid  = readFsr(PIN_FSR_MIDFOOT);
  toe  = readFsr(PIN_FSR_TOE);
}

float readTemperature() {
  tempSensor.requestTemperatures();
  float t = tempSensor.getTempCByIndex(0);
  if (t == DEVICE_DISCONNECTED_C) return NAN;   // sensor unplugged
  return t;
}

// Classify motion from acceleration. The Adafruit library returns m/s^2.
// Thresholds are starting guesses - tune them against real data.
MotionState readMotion() {
  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  // Total acceleration minus gravity (9.81) = how much the foot is moving
  float mag = sqrt(a.acceleration.x * a.acceleration.x +
                   a.acceleration.y * a.acceleration.y +
                   a.acceleration.z * a.acceleration.z);
  float movement = fabs(mag - 9.81f);

  if (movement > 2.0f) return WALKING;
  // Foot flat & still: use total pressure to tell sitting from standing
  float h, m, t;
  readPressure(h, m, t);
  return ((h + m + t) > 60.0f) ? STANDING : SITTING;
}

int readBatteryPercent() {
  // Assumes a 1:2 voltage divider on a 1-cell LiPo (3.0 V empty, 4.2 V full).
  float volts = (analogRead(PIN_BATTERY) / 4095.0f) * 3.3f * 2.0f;
  int pct = (int)((volts - 3.0f) / (4.2f - 3.0f) * 100.0f);
  return constrain(pct, 0, 100);
}

#endif

// ===================== SIMULATED CLOCK ==========================
// The ESP32 has no real-time clock yet. We fake one that starts at the
// contract's example time and advances in real time. Later: replace
// with NTP (configTime) or an RTC module like the DS3231.
time_t simStartEpoch;

void initClock() {
  struct tm t = {};
  t.tm_year = START_YEAR - 1900;
  t.tm_mon  = START_MONTH - 1;
  t.tm_mday = START_DAY;
  t.tm_hour = START_HOUR;
  t.tm_min  = START_MIN;
  t.tm_sec  = START_SEC;
  simStartEpoch = mktime(&t);   // TZ is unset on ESP32, so this acts as UTC
}

// Writes "YYYY-MM-DDTHH:MM:SS" (no timezone suffix, as in the contract)
void getTimestamp(char *out, size_t len) {
  time_t now = simStartEpoch + (millis() / 1000);
  struct tm t;
  localtime_r(&now, &t);
  strftime(out, len, "%Y-%m-%dT%H:%M:%S", &t);
}

// ===================== JSON OUTPUT ==============================
// Builds the JSON by hand (no library) so key order and number format
// stay exactly what the data contract shows.
void printReading(const Reading &r, const char *timestamp) {
  // Missing temperature sensor -> print null instead of invalid "nan"
  char tempStr[16];
  if (isnan(r.temperatureC)) strcpy(tempStr, "null");
  else snprintf(tempStr, sizeof(tempStr), "%.1f", r.temperatureC);

  if (PRETTY_PRINT) {
    Serial.printf("{\n");
    Serial.printf("  \"device_id\": \"%s\",\n", DEVICE_ID);
    Serial.printf("  \"user_id\": \"%s\",\n", USER_ID);
    Serial.printf("  \"timestamp\": \"%s\",\n", timestamp);
    Serial.printf("  \"pressure\": { \"heel\": %.1f, \"midfoot\": %.1f, \"toe\": %.1f },\n",
                  r.heel, r.midfoot, r.toe);
    Serial.printf("  \"temperature_celsius\": %s,\n", tempStr);
    Serial.printf("  \"motion_state\": \"%s\",\n", motionToString(r.motion));
    Serial.printf("  \"battery_percent\": %d\n", r.batteryPercent);
    Serial.printf("}\n");
  } else {
    // One line per reading = easy for the app/ML code to parse
    Serial.printf(
      "{\"device_id\":\"%s\",\"user_id\":\"%s\",\"timestamp\":\"%s\","
      "\"pressure\":{\"heel\":%.1f,\"midfoot\":%.1f,\"toe\":%.1f},"
      "\"temperature_celsius\":%s,\"motion_state\":\"%s\",\"battery_percent\":%d}\n",
      DEVICE_ID, USER_ID, timestamp,
      r.heel, r.midfoot, r.toe,
      tempStr, motionToString(r.motion), r.batteryPercent);
  }
}

// ===================== ARDUINO ENTRY POINTS =====================
void setup() {
  Serial.begin(115200);
  delay(500);

  initClock();

#if SIMULATE_SENSORS
  // Seed the random generator from floating ADC noise so each boot differs
  randomSeed(analogRead(0));
  simStateStartMs = millis();
#else
  analogReadResolution(12);          // 0-4095
  tempSensor.begin();
  if (!mpu.begin()) {
    // Print to Serial as a non-JSON line starting with '#' so parsers can skip it
    Serial.println("# ERROR: MPU6050 not found - check wiring");
  } else {
    mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
    mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  }
#endif
}

void loop() {
  static unsigned long lastSampleMs = 0;

  // Non-blocking timing: no delay(), so the loop can do other work later
  // (BLE, WiFi, etc.)
  if (millis() - lastSampleMs >= SAMPLE_INTERVAL_MS) {
    lastSampleMs = millis();

    Reading r;
    readPressure(r.heel, r.midfoot, r.toe);
    r.temperatureC   = readTemperature();
    r.motion         = readMotion();
    r.batteryPercent = readBatteryPercent();

    char ts[24];
    getTimestamp(ts, sizeof(ts));

    printReading(r, ts);
  }
}
