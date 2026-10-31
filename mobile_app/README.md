# SoleGuard Mobile App (`mobile_app/`)

Flutter app for SoleGuard, a smart insole for personalized foot-risk monitoring in diabetic nurses. It shows pressure and temperature readings with a risk banner (normal / caution / alert).

**Status:** working prototype. It plays back recorded sample shifts and shows the **ML module's alerts** (from `ml_personalization`). It is not connected to real hardware or Bluetooth yet.

## Where the data comes from

All demo data is in `assets/app_demo/`. It is a copy of the files Person C exported to `data/app_demo/` on the `ml-personalization` branch:

- `nurses.json`: the 10 nurse profiles (same cohort as the team's cohort Excel).
- `sample_shift_nurseNN.json`: 200 sensor readings per nurse, 30 seconds apart, in the data-contract sensor format.
- `alerts_nurseNN.json`: the ML output, one alert per reading with the same timestamp, in the data-contract alert format.

The app pairs each reading with the ML alert that has the same timestamp. If Person C regenerates the data, copy the new files from `data/app_demo/` into `mobile_app/assets/app_demo/` and run the app again.

If an alert file is missing, the app falls back to simple fixed-limit backup rules (`RiskAlert.evaluate` in `lib/models/alert.dart`) and shows a "Backup rules in use" chip. The backup rules ignore each nurse's personal baseline, so they are only a safety net.

## Screens

| Screen | What it does |
|---|---|
| Login | Sign in as one of the 10 demo nurses. Tap a nurse in the demo list to fill the form. |
| Dashboard | Risk banner with the ML reasons, heel / midfoot / toe pressure, temperature, motion and battery. Playback controls and a shift timeline. |
| History | Trend chart (heel, midfoot, toe or temperature) with bands where the ML model raised an alert, counts, and a list of readings. Filter to caution and alert only. |
| Profile | Nurse details, health profile from `nurses.json`, device ID, demo scenario, log out. |

### Dashboard details

- **Banner:** shows the ML `risk_level` and every line of the ML `reason`.
- **Tile colors:** a pressure or temperature tile is highlighted only when the ML reason names that zone, with the SD value from the reason (for example "+3.5 SD"). Because the ML model compares each nurse with their own baseline, a tile is never colored just because a value looks high. If the wording of the ML reason changes, tiles simply stay neutral and the banner is still correct.
- **Playback:** play/pause, speed (1×, 3×, 10×; 1× is one reading every 3 seconds), **Prev alert / Next alert** buttons that jump to the start of the previous or next caution/alert episode, and a timeline you can tap or drag. Orange and red marks on the timeline show where the ML model raised alerts.

## Demo accounts

Each nurse has a short password: username `n1` uses `p1`, `n2` uses `p2`, and so on up to `n10` with `p10`. On the login screen you can also tap a nurse in the demo list to fill both fields.

The last column is the number of readings the ML model rated normal / caution / alert.

| Username | User ID | Name | Ward | Scenario | Normal / caution / alert |
|---|---|---|---|---|---|
| `n1` | NURSE-01 | Anitha D'Souza | Medical ward | Stable all shift, stays within own normal | 200 / 0 / 0 |
| `n2` | NURSE-02 | Rekha Shetty | Surgical ward | Heel pressure rises after long standing; temperature normal | 180 / 17 / 3 |
| `n3` | NURSE-03 | Fathima Noor | ICU | Foot temperature rises in short hot-spot episodes; pressure normal | 185 / 15 / 0 |
| `n4` | NURSE-04 | Savitha Rao | Operation theatre | Pressure and temperature both rise, repeatedly | 177 / 3 / 20 |
| `n5` | NURSE-05 | Joseph Pinto | Emergency | High readings by other nurses' standards, but normal and stable for this nurse | 200 / 0 / 0 |
| `n6` | NURSE-06 | Deepa Nayak | Paediatric ward | Toe (forefoot) pressure rises, mostly while standing; temperature normal | 182 / 15 / 3 |
| `n7` | NURSE-07 | Lakshmi Bhat | ICU | Long standing stretches with pressure and temperature rising together | 153 / 3 / 44 |
| `n8` | NURSE-08 | Mohammed Rafiq | Medical ward | Stable all shift, stays within own normal | 200 / 0 / 0 |
| `n9` | NURSE-09 | Prema Kumari | Maternity ward | Foot temperature drifts upward through the second half of the shift; pressure normal | 145 / 55 / 0 |
| `n10` | NURSE-10 | Sunitha George | Surgical ward | Mild rise in both pressure and temperature | 182 / 7 / 11 |

## How to run

Requirements: [Flutter SDK](https://docs.flutter.dev/get-started/install) (developed with Flutter 3.29.3).

```bash
cd mobile_app
flutter pub get
flutter run -d chrome
```

To preview at phone size in Chrome: open developer tools (Ctrl+Shift+I), toggle device mode (Ctrl+Shift+M) and pick a phone.

To check the app against the ML files (10 nurses, 200 readings each, expected alert counts):

```bash
flutter test test/risk_scenarios_test.dart
```

Only Chrome (web) has been tested so far. Android and iOS builds have not been tested yet.

## Data contract

The app follows the team data contract exactly (see `docs/data-contract.md`).

Sensor reading:

```json
{
  "device_id": "INSOLE-001",
  "user_id": "NURSE-01",
  "timestamp": "2026-10-08T07:00:00",
  "pressure": { "heel": 42.5, "midfoot": 18.2, "toe": 30.1 },
  "temperature_celsius": 33.4,
  "motion_state": "standing",
  "battery_percent": 78
}
```

`motion_state` is `standing`, `walking` or `sitting` in the sample data.

Alert (output of the ML module):

```json
{
  "user_id": "NURSE-01",
  "timestamp": "2026-10-08T07:00:00",
  "risk_level": "normal",
  "reason": null
}
```

## Project structure

```
mobile_app/
├── pubspec.yaml
├── assets/app_demo/           nurses.json, sample shifts and ML alerts
├── test/
│   └── risk_scenarios_test.dart
└── lib/
    ├── main.dart              app entry, loads nurses, starts at login
    ├── models/
    │   ├── sensor_reading.dart    sensor reading (matches contract)
    │   ├── alert.dart             alert (matches contract), reason helpers, backup rules
    │   └── user.dart              nurse profile
    ├── services/
    │   ├── auth_service.dart      local demo login
    │   └── shift_repository.dart  loads a shift and pairs readings with ML alerts
    ├── widgets/
    │   └── ui_helpers.dart        colors, icons, time formatting
    └── screens/
        ├── login_screen.dart
        ├── home_shell.dart        loads the shift once, bottom navigation
        ├── dashboard_screen.dart
        ├── history_screen.dart
        └── profile_screen.dart
```

## What is real and what is placeholder

- **Risk level:** comes from the ML module's exported alerts. The alerts are precomputed from the sample data, not calculated live in the app.
- **Sensor data:** recorded sample shifts, not live data from the insole. Bluetooth is not implemented yet.
- **Login:** credentials are checked against the demo nurses in `nurses.json`. The passwords are plain text in the source code and there is no server. This is a demo only. Do not use it for real patient data. For production, use a real authentication backend, HTTPS/TLS for all network calls, and encrypted storage on the device.
- **Nurse profiles:** the names and health details are simulated test data, not real people.

## Planned next steps

- Connect to the insole over Bluetooth Low Energy once hardware is available.
- Run the ML module on live readings instead of precomputed alerts.
- Test on Android hardware.

## Owner

Mobile app: Person B. ML module: Person C.
