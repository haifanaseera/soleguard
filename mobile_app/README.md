# SoleGuard Mobile App (`mobile_app/`)

Flutter app for SoleGuard, a smart insole for personalized foot-risk monitoring in diabetic nurses. It shows live pressure and temperature readings and a risk banner (normal / caution / alert).

**Status:** working prototype running on local sample data. No hardware, Bluetooth or ML connection yet.

## Screens

| Screen | What it does |
|---|---|
| Login | Sign in as one of 10 demo nurses. Tap a demo account in the list to fill the form. Validation, loading state, error feedback. |
| Dashboard | Current heel / midfoot / toe pressure, temperature, motion state, battery, and a colored risk banner. Pressure tiles and the temperature card turn orange or red when that value is over its threshold. Cycles through the sample readings every 3 seconds to simulate a live feed. |
| History | Pressure trend chart (switch between heel, midfoot and toe) and a list of past readings, each with its risk level and reason. |
| Profile | Nurse name, ward, device ID, demo scenario, log out. |

## Demo accounts

Password for every account: `password123`

| Username | User ID | Scenario | Expected risk over the shift |
|---|---|---|---|
| `n1` | NURSE-A | Normal, steady standing | normal throughout |
| `n2` | NURSE-B | Normal, active walking | normal throughout |
| `n3` | NURSE-C | Normal, borderline values (just under every threshold) | normal throughout |
| `n4` | NURSE-D | Heel pressure rising | normal, then caution, then alert |
| `n5` | NURSE-E | Midfoot pressure rising | normal, then caution, then alert |
| `n6` | NURSE-F | Toe pressure rising | normal, then caution, then alert |
| `n7` | NURSE-G | Temperature rising only (pressure normal) | normal, then caution, then alert |
| `n8` | NURSE-H | Prolonged standing, 2h+ (pressure moderate) | normal, caution at 45 min, alert at 90 min |
| `n9` | NURSE-I | Heel pressure and temperature rising together | normal, then caution, then alert (both reasons shown) |
| `n10` | NURSE-J | Starts in alert, then recovers while walking | alert, then caution, then normal |

## Risk rules (placeholder)

These stand in for the ML module. They live in `lib/models/alert.dart` (`RiskThresholds` and `RiskAlert.evaluate`). The worst finding wins, and if several share the worst level, all their reasons are shown.

| Signal | Caution | Alert |
|---|---|---|
| Heel pressure | above 60 kPa | above 80 kPa |
| Midfoot pressure | above 40 kPa | above 55 kPa |
| Toe pressure | above 50 kPa | above 65 kPa |
| Temperature | above 36.5 °C | above 37.5 °C |
| Continuous standing | 45 min or more | 90 min or more |

These numbers are placeholders chosen for the demo, not clinical values. Check them with whoever owns the ML module.

## How to run

Requirements: [Flutter SDK](https://docs.flutter.dev/get-started/install) (developed with Flutter 3.29.3).

```bash
cd mobile_app
flutter pub get
flutter run -d chrome
```

To preview at phone size in Chrome: open developer tools (Ctrl+Shift+I), toggle device mode (Ctrl+Shift+M) and pick a phone.

To check the risk rules against all 10 demo nurses:

```bash
flutter test test/risk_scenarios_test.dart
```

Only Chrome (web) has been tested so far. Android and iOS builds have not been tested yet.

## Data contract

The app follows the team data contract exactly (see `docs/data-contract.md`).

Sensor reading (input):

```json
{
  "device_id": "INSOLE-001",
  "user_id": "NURSE-A",
  "timestamp": "2026-09-24T14:32:00",
  "pressure": { "heel": 42.5, "midfoot": 18.2, "toe": 30.1 },
  "temperature_celsius": 33.4,
  "motion_state": "standing",
  "battery_percent": 78
}
```

Alert (output of the ML module):

```json
{
  "user_id": "NURSE-A",
  "timestamp": "2026-09-24T14:32:00",
  "risk_level": "normal",
  "reason": null
}
```

Sample data lives in `assets/sample_shift_nurseA.json` to `sample_shift_nurseJ.json`. Each file is an array of readings in the sensor format above. `motion_state` is `standing` or `walking` in the sample data. Readings are 5 seconds apart, except NURSE-H, whose readings are 15 minutes apart to show a long shift.

## Project structure

```
mobile_app/
├── pubspec.yaml
├── assets/                    sample shift data (one file per nurse)
├── test/
│   └── risk_scenarios_test.dart   checks the risk rules for all 10 nurses
└── lib/
    ├── main.dart              app entry, theme, starts at login
    ├── models/
    │   ├── sensor_reading.dart    sensor reading model (matches contract)
    │   ├── alert.dart             alert model (matches contract) + placeholder risk rules
    │   └── user.dart              nurse profile model
    ├── services/
    │   └── auth_service.dart      local demo login and the 10 demo nurses
    └── screens/
        ├── login_screen.dart
        ├── home_shell.dart        bottom navigation
        ├── dashboard_screen.dart
        ├── history_screen.dart
        └── profile_screen.dart
```

## What is real and what is placeholder

**Placeholder (to be replaced):**

- **Risk level.** `RiskAlert.evaluate()` in `lib/models/alert.dart` uses the thresholds above. It is called in two places: `dashboard_screen.dart` and `history_screen.dart`. When the ML module is ready, replace those calls with alerts loaded in the contract format. `RiskAlert.fromJson()` already parses that format.
- **Sensor data.** Read from local JSON files instead of the insole over Bluetooth.
- **Login.** Credentials are checked against a hardcoded list in `lib/services/auth_service.dart`. This is a demo only: the password is stored in plain text in the source code and there is no server. Do not use it for real patient data. For production, use a real authentication backend, HTTPS/TLS for all network calls, and encrypted storage on the device.

## Planned next steps

- Connect to the insole over Bluetooth Low Energy once hardware is available.
- Replace the placeholder risk rules with the ML module's output.
- Test on Android hardware.

## Owner

Mobile app: Person B.
