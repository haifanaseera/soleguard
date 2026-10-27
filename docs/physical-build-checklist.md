# SoleGuard: Physical Build Checklist

Owner: Person A (firmware). Tick each box as it is done: `- \[x]`.
Prices are rough INR estimates for India and must be rechecked before ordering.

\---

## Phase 0: Team sign-off (before buying or building)

* \[ ] **Temperature on sensor failure:** firmware sends `null` for `temperature\_celsius` when the DS18B20 is unplugged. App and ML teammates confirm they can handle `null` (or agree on another value).
* \[ ] **Pressure units:** agree on raw ADC, a calibrated 0-100 scale, or kPa for the first prototype.
* \[ ] **Time source:** replace the simulated clock. Options: phone sends the current time over BLE on connect (easiest), DS3231 RTC module, or NTP over WiFi.
* \[ ] **Connection type:** BLE (current firmware) or WiFi.
* \[ ] **Scope noted in README:** this is a student prototype, not a medical device. Nothing from it is used for clinical decisions.
* \[x] **BLE identifiers shared with the mobile app teammate:**

  * Device name: `SoleGuard-001`
  * Service UUID: `5a3b0001-6f1e-4c1a-9a53-501e6a7d0001`
  * Characteristic UUID: `5a3b0002-6f1e-4c1a-9a53-501e6a7d0001` (notify)
  * Each reading is sent in 20-byte chunks and ends with `\\n`.

\---

## Phase 1: Parts

### 1A. Bench build (order now)

|Done|Part|Qty|Check when buying|Est. price (INR)|
|-|-|-|-|-|
|\[x]|ESP32 DevKit, 30-pin|1 (2nd optional)|Labels GPIO34, 35, 32, 33, 4, 21, 22; note USB chip (CP2102 or CH340)|400-650|
|\[x]|FSR 402 (0.5 inch / 12.7 mm round)|4 (3 + 1 spare)|Round pad, not the large square FSR|\~245 each|
|\[x]|MPU6050 GY-521 module|1|Pre-soldered headers; seller with good reviews (avoid fake chips)|150-250|
|\[x]|DS18B20 temperature sensor|1|Waterproof probe is easiest to wire|100-200|
|\[ ]|Resistor 10 kΩ|4|3 FSR dividers + 1 spare|cheap|
|\[ ]|Resistor 4.7 kΩ|2|DS18B20 pull-up + 1 spare|cheap|
|\[ ]|Resistor 100 kΩ|3|Battery divider (2) + 1 spare|cheap|
|\[x]|Breadboard (half-size is enough)|1||60-120|
|\[x]|Jumper wires (M-M and M-F)|1 pack||60-100|
|\[x]|Micro-USB cable|1|**Must carry data**, not charge-only|own|
|\[ ]|USB power bank|1|Used for bench power|own|
|\[ ]|Multimeter|1|Basic is fine, or borrow|own/borrow|
|\[ ]|Reference thermometer|1|Kitchen or fever thermometer|own|
|\[ ]|Known weights|-|Water bottles or kitchen scale|own|

### 1B. Wearable build (order after Phases 3 and 4 pass)

|Done|Part|Qty|Check when buying|
|-|-|-|-|
|\[x]|LiPo 3.7 V, about 2000 mAh|1|**Must have protection board (PCM)**|
|\[x]|TP4056 charger module with protection|1|6-pad version (B+, B-, OUT+, OUT-, IN+, IN-)|
|\[x]|MT3608 5 V boost converter|1|Set output to 5 V with a multimeter **before** connecting the ESP32|
|\[ ]|Thin silicone wire (26-30 AWG)|1 set||
|\[ ]|Heat-shrink tubing|1 set||
|\[ ]|Small enclosure|1|For ankle or shoe-side mounting|
|\[ ]|Insole and thin tape|1||

**Rules:** never connect a LiPo directly to the ESP32. Never use a LiPo without protection. Keep the battery off the foot.

\---

## Phase 2: Wiring

|Part|Connection|
|-|-|
|FSR heel|3.3 V → FSR → **GPIO34**; same node → 10 kΩ → GND|
|FSR midfoot|3.3 V → FSR → **GPIO35**; same node → 10 kΩ → GND|
|FSR toe|3.3 V → FSR → **GPIO32**; same node → 10 kΩ → GND|
|DS18B20|Red → 3.3 V, Black → GND, Data → **GPIO4**, 4.7 kΩ between Data and 3.3 V|
|MPU6050|VCC → 3.3 V, GND → GND, SDA → **GPIO21**, SCL → **GPIO22**|
|Battery sense|Battery+ → 100 kΩ → **GPIO33** → 100 kΩ → GND|
|Power (wearable)|LiPo → TP4056 → MT3608 (5 V) → ESP32 VIN|

* \[ ] Wiring double-checked against the pin constants at the top of `soleguard\_firmware.ino`.
* \[ ] Nothing connected to GPIO34/35 other than the FSR dividers (these pins are input-only).

\---

## Phase 3: Bench bring-up (breadboard, sensors off the insole)

* \[ ] Arduino IDE: install libraries **OneWire**, **DallasTemperature**, **Adafruit MPU6050** (plus Adafruit Unified Sensor and BusIO).
* \[ ] Test each sensor alone with the library example sketches.
* \[ ] Set `SIMULATE\_SENSORS 0` in `soleguard\_firmware.ino`.
* \[ ] Firmware improvements before trusting real data:

  * \[ ] Real time source (see Phase 0)
  * \[ ] Motion classified over a 1-second window, not a single sample
  * \[ ] DS18B20 read made non-blocking (currently blocks about 0.75 s)
  * \[ ] Average several FSR readings to reduce noise
  * \[ ] All calibration constants in one block at the top of the file
* \[ ] **FSR calibration:** record readings at 0, 2, 5 and 10 kg in a table in `docs/`.
* \[ ] **Temperature check:** compare against the reference thermometer at room temperature and in warm water.
* \[ ] **Battery check:** compare reported `battery\_percent` with the multimeter reading.

\---

## Phase 4: Integration

* \[ ] Phone app connects to `SoleGuard-001` over BLE and parses the JSON.
* \[ ] Confirm with nRF Connect that notifications arrive as text chunks ending in `\\n`.
* \[ ] 30-minute continuous run with no resets.

\---

## Phase 5: Insole assembly (only after Phases 3 and 4 pass)

* \[ ] FSRs placed at heel, arch and forefoot, covered with thin tape.
* \[ ] Wires routed along the insole edge.
* \[ ] ESP32 and battery in an enclosure at the ankle or shoe side, not under the foot.
* \[ ] All joints insulated; battery away from skin.

\---

## Phase 6: Field test

* \[ ] 15-minute walk with consent of the wearer.
* \[ ] Longer wear test.

\---

## Acceptance criteria (the build is done when all pass)

|Done|Area|Test|Pass condition|
|-|-|-|-|
|\[ ]|Contract|Capture 1000 readings and validate|All parse as JSON with the exact keys, key order and types; values in range|
|\[ ]|Timing|10-minute run|One reading per second (±0.1 s), no resets|
|\[ ]|Pressure|Unloaded, then known weights|Near zero unloaded, increases with load, repeats within ±10%|
|\[ ]|Temperature|Compare with reference thermometer|Within ±0.5 °C from 25 to 40 °C|
|\[ ]|Motion|20 trials each: sitting, standing, walking|At least 90% correctly classified|
|\[ ]|Battery|Compare with multimeter|Within ±5%; runtime target agreed by the team and measured|
|\[ ]|Clock|Compare with phone|Timestamps within 2 s|
|\[ ]|BLE|30 minutes at 5 m, plus forced disconnect|No lines lost; reconnects in about 15 s|
|\[ ]|App|Live view|App shows live values from real data|
|\[ ]|Safety|Wear for 15 minutes|No exposed battery or wires against skin, nothing hot, comfortable, sweat-protected|
|\[ ]|Process|Final check|Code compiles, committed to `firmware/`, README documents wiring and calibration|

\---

## Notes and results

(Record calibration tables, test dates and issues here.)

