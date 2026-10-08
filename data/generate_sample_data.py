# ============================================================
# SoleGuard - Fake Sensor Data Generator
# ============================================================
# Generates realistic sample sensor readings matching the
# data contract (docs/data-contract.md), simulating a full
# nurse shift with occasional abnormal spikes mixed in.
# Used by the app and ML teammates to build/test their parts
# before real hardware exists.
#
# Each nurse has her own "profile": NURSE-B naturally loads
# her feet harder and runs warmer than NURSE-A, so the ML
# module's personalized baselines actually have something
# different to learn. The JSON schema is unchanged.
# ============================================================

import json
import random
from datetime import datetime, timedelta
from pathlib import Path

# Offsets added to every pressure/temperature value for that nurse.
PROFILES = {
    "NURSE-A": {"device_id": "INSOLE-001", "heel": 0, "midfoot": 0, "toe": 0, "temp": 0.0},
    "NURSE-B": {"device_id": "INSOLE-002", "heel": 25, "midfoot": 0, "toe": 20, "temp": 1.5},
}
NEUTRAL_PROFILE = {"device_id": "INSOLE-001", "heel": 0, "midfoot": 0, "toe": 0, "temp": 0.0}


def generate_shift_data(user_id="NURSE-A", num_readings=200, start_time=None, profile=None):
    """
    Generates a list of sensor readings simulating one shift.
    Roughly 5% of readings are intentionally abnormal (spikes),
    so the ML teammate has real anomalies to detect.

    profile: optional dict overriding the nurse's offsets. By default
    it is looked up from PROFILES by user_id (unknown ids get no offset).
    """
    if profile is None:
        profile = PROFILES.get(user_id, NEUTRAL_PROFILE)

    if start_time is None:
        start_time = datetime.now()

    readings = []
    current_time = start_time

    for i in range(num_readings):
        is_abnormal = random.random() < 0.05  # 5% chance of a spike

        if is_abnormal:
            heel = random.uniform(70, 90)
            midfoot = random.uniform(15, 25)
            toe = random.uniform(60, 80)
            temp = random.uniform(36, 38)
            motion = "standing"
        else:
            heel = random.uniform(35, 45)
            midfoot = random.uniform(15, 22)
            toe = random.uniform(25, 35)
            temp = random.uniform(32, 34)
            motion = random.choice(["standing", "walking", "sitting"])

        reading = {
            "device_id": profile["device_id"],
            "user_id": user_id,
            "timestamp": current_time.isoformat(),
            "pressure": {
                "heel": round(heel + profile["heel"], 1),
                "midfoot": round(midfoot + profile["midfoot"], 1),
                "toe": round(toe + profile["toe"], 1),
            },
            "temperature_celsius": round(temp + profile["temp"], 1),
            "motion_state": motion,
            "battery_percent": max(20, 100 - (i // 5)),
        }
        readings.append(reading)
        current_time += timedelta(seconds=30)

    return readings


def sample_path(user_id):
    """data/sample_shift_nurseA.json for NURSE-A, etc. (always inside data/)."""
    letter = user_id.replace("NURSE-", "")
    return Path(__file__).parent / f"sample_shift_nurse{letter}.json"


if __name__ == "__main__":
    for uid in PROFILES:
        data = generate_shift_data(user_id=uid, num_readings=200)
        out = sample_path(uid)
        with open(out, "w") as f:
            json.dump(data, f, indent=2)
        print(f"Generated {len(data)} readings for {uid} -> {out.name}")
