# SoleGuard — Data Contract

This is the agreed JSON structure for sensor data flowing from the insole (ESP32) to the mobile app and ML module. All three team members must follow this exact format.

## Sensor Reading Schema

```json
{
  "device_id": "INSOLE-001",
  "user_id": "NURSE-A",
  "timestamp": "2026-09-24T14:32:00",
  "pressure": {
    "heel": 42.5,
    "midfoot": 18.2,
    "toe": 30.1
  },
  "temperature_celsius": 33.4,
  "motion_state": "standing",
  "battery_percent": 78
}
```

## Field Notes

- `device_id`: unique identifier for the insole unit
- `user_id`: identifies which team member's data this is (for personalized baseline tracking)
- `timestamp`: ISO 8601 format
- `pressure`: values in kPa (or raw ADC value initially — to be calibrated later), one per sensor zone
- `temperature_celsius`: reading from the DS18B20 sensor
- `motion_state`: one of `"standing"`, `"walking"`, `"sitting"` — derived from MPU6050 motion data
- `battery_percent`: 0–100, remaining battery on the ESP32 unit

## Alert Output Schema (from ML module → app)

```json
{
  "user_id": "NURSE-A",
  "timestamp": "2026-09-24T14:32:00",
  "risk_level": "normal",
  "reason": null
}
```

- `risk_level`: one of `"normal"`, `"caution"`, `"alert"`
- `reason`: short text explaining why (e.g. `"Heel pressure 3.2 std dev above baseline"`), null if normal
