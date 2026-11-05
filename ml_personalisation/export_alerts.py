# ============================================================
# SoleGuard - Export alert JSON files for the mobile app
# ============================================================
# Runs the ML module on the shared sample shift data and writes
# the result in the locked alert format:
#     user_id, timestamp, risk_level, reason
#
# Run from the repo root (after generate_sample_data.py):
#     python ml_personalisation/export_alerts.py
#
# Writes into data/ so the app can load them the same way it
# loads the sensor data:
#   alerts_nurseA.json / alerts_nurseB.json
#       One alert per sensor reading, same order and timestamps as
#       sample_shift_nurseA.json / sample_shift_nurseB.json.
#       The first 60 readings (30 min) are the calibration phase:
#       the system is still learning the nurse's baseline, so they
#       are reported as "normal" with reason null.
#   alerts_demo_all_levels.json
#       Three alerts (normal, caution, alert) so the app's banners
#       can be tested without hunting through a whole shift.
# ============================================================

import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
DATA_DIR = HERE.parent / "data"
sys.path.insert(0, str(HERE))

from personalization import PersonalBaseline, RiskDetector

CALIBRATION_READINGS = 60  # first 30 minutes (60 x 30 s)

NURSES = {
    "NURSE-A": "nurseA",
    "NURSE-B": "nurseB",
}


def load_shift(letter):
    path = DATA_DIR / f"sample_shift_{letter}.json"
    if not path.exists():
        sys.exit(
            f"Missing {path.name}. Run  python data/generate_sample_data.py  first."
        )
    with open(path) as f:
        return json.load(f)


def build_alerts(readings):
    """Return (baseline, alerts) with one alert per reading."""
    user_id = readings[0]["user_id"]
    baseline = PersonalBaseline.calibrate(user_id, readings[:CALIBRATION_READINGS])

    alerts = [
        {
            "user_id": r["user_id"],
            "timestamp": r["timestamp"],
            "risk_level": "normal",
            "reason": None,
        }
        for r in readings[:CALIBRATION_READINGS]
    ]

    detector = RiskDetector(baseline)
    alerts += [detector.evaluate(r) for r in readings[CALIBRATION_READINGS:]]
    return baseline, alerts


def build_demo_alerts(baseline):
    """One normal, one caution and one alert, based on NURSE-A's baseline."""
    mean = {s: v["mean"] for s, v in baseline.stats.items()}

    def reading(timestamp, heel, temp):
        return {
            "device_id": "INSOLE-001",
            "user_id": baseline.user_id,
            "timestamp": timestamp,
            "pressure": {
                "heel": round(heel, 1),
                "midfoot": round(mean["midfoot"], 1),
                "toe": round(mean["toe"], 1),
            },
            "temperature_celsius": round(temp, 1),
            "motion_state": "walking",
            "battery_percent": 80,
        }

    samples = [
        reading("2026-10-08T12:00:00", mean["heel"], mean["temperature"]),           # normal
        reading("2026-10-08T12:00:30", mean["heel"] + 20, mean["temperature"]),      # heel only -> caution
        reading("2026-10-08T12:01:00", mean["heel"] + 30, mean["temperature"] + 3),  # heel + temp -> alert
    ]
    return [RiskDetector(baseline).evaluate(r) for r in samples]


def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    baseline_a = None
    for user_id, letter in NURSES.items():
        readings = load_shift(f"{letter}")
        baseline, alerts = build_alerts(readings)
        out = DATA_DIR / f"alerts_{letter}.json"
        write_json(out, alerts)

        counts = {}
        for a in alerts:
            counts[a["risk_level"]] = counts.get(a["risk_level"], 0) + 1
        print(f"{user_id}: {len(alerts)} alerts -> {out.name}  {counts}")

        if user_id == "NURSE-A":
            baseline_a = baseline

    demo = build_demo_alerts(baseline_a)
    demo_out = DATA_DIR / "alerts_demo_all_levels.json"
    write_json(demo_out, demo)
    print(f"Demo (normal / caution / alert) -> {demo_out.name}")
    for a in demo:
        print(f"  {a['risk_level']:<8} {a['reason']}")
