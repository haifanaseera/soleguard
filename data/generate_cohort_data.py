# ============================================================
# SoleGuard - Simulated 10-Nurse Cohort Generator
# ============================================================
# Creates one simulated shift (200 readings, every 30 s) for 10
# different nurses, in the locked data contract format.
#
# Every nurse has her OWN normal (baseline) and her own pattern,
# so the cohort covers the cases our guide asked for:
#   - no signs at all
#   - pressure elevated only
#   - temperature elevated only
#   - both pressure and temperature elevated
#
# ALL DATA HERE IS SIMULATED. It stands in for real insole data
# until the hardware is built and volunteers can be recorded.
#
# Run from the repo root:   python data/generate_cohort_data.py
# Writes:  data/cohort_10_nurses.json
# Then prints how the ML module (personalization.py) classifies
# each nurse, if the ML folder can be found.
# ============================================================

import json
import random
import sys
from datetime import datetime, timedelta
from pathlib import Path

SEED = 7
NUM_READINGS = 200
CALIBRATION_READINGS = 60            # first 30 min = learning phase
START_TIME = datetime(2026, 10, 8, 7, 0, 0)

# offsets = (heel, midfoot, toe, temperature): shifts this nurse's
#           normal up or down, so every nurse has her own baseline.
# episodes = stretches of the shift where she deviates from HER normal:
#   start/length (in readings), extra pressure/temperature, and
#   standing=True to force the "standing" motion state.
#   ramp=True makes the extra rise gradually instead of at once.
NURSES = [
    {"id": "NURSE-01", "category": "No signs",
     "pattern": "Stable all shift, stays within her own normal",
     "offsets": (0, 0, 0, 0.0), "episodes": []},

    {"id": "NURSE-02", "category": "Pressure only",
     "pattern": "Heel pressure rises after long standing; temperature normal",
     "offsets": (4, 1, 2, -0.2),
     "episodes": [
         {"start": 72, "length": 5, "heel": 8, "standing": True},
         {"start": 110, "length": 14, "heel": 12, "standing": True},
         {"start": 160, "length": 6, "heel": 7},
     ]},

    {"id": "NURSE-03", "category": "Temperature only",
     "pattern": "Foot temperature rises in short hot-spot episodes; pressure normal",
     "offsets": (-3, 0, -2, 0.3),
     "episodes": [
         {"start": 70, "length": 6, "temp": 1.6},
         {"start": 118, "length": 9, "temp": 2.6},
         {"start": 172, "length": 5, "temp": 1.5},
     ]},

    {"id": "NURSE-04", "category": "Both",
     "pattern": "Pressure and temperature both rise, repeatedly",
     "offsets": (6, 1, 3, 0.2),
     "episodes": [
         {"start": 68, "length": 6, "heel": 12, "toe": 10, "temp": 2.5, "standing": True},
         {"start": 115, "length": 10, "heel": 14, "toe": 12, "temp": 3.0, "standing": True},
         {"start": 165, "length": 7, "heel": 9, "toe": 7, "temp": 2.0},
     ]},

    {"id": "NURSE-05", "category": "No signs",
     "pattern": "High readings by other nurses' standards, but normal and stable for her",
     "offsets": (25, 2, 20, 1.5), "episodes": []},

    {"id": "NURSE-06", "category": "Pressure only",
     "pattern": "Toe (forefoot) pressure rises, mostly while standing; temperature normal",
     "offsets": (2, 3, -1, -0.1),
     "episodes": [
         {"start": 80, "length": 5, "toe": 9},
         {"start": 130, "length": 13, "toe": 11, "standing": True},
         {"start": 175, "length": 5, "toe": 8},
     ]},

    {"id": "NURSE-07", "category": "Both",
     "pattern": "Long standing stretches with pressure and temperature rising together",
     "offsets": (8, 0, 5, 0.4),
     "episodes": [
         {"start": 64, "length": 9, "heel": 10, "toe": 8, "temp": 2.2, "standing": True},
         {"start": 98, "length": 14, "heel": 13, "toe": 10, "temp": 2.8, "standing": True},
         {"start": 138, "length": 12, "heel": 12, "toe": 9, "temp": 2.6, "standing": True},
         {"start": 178, "length": 10, "heel": 14, "toe": 11, "temp": 3.0, "standing": True},
     ]},

    {"id": "NURSE-08", "category": "No signs",
     "pattern": "Stable all shift, stays within her own normal",
     "offsets": (-2, -1, 1, -0.2), "episodes": []},

    {"id": "NURSE-09", "category": "Temperature only",
     "pattern": "Foot temperature drifts upward through the second half of the shift; pressure normal",
     "offsets": (1, 0, 1, 0.1),
     "episodes": [
         {"start": 100, "length": 100, "temp": 2.8, "ramp": True},
     ]},

    {"id": "NURSE-10", "category": "Both",
     "pattern": "Mild rise in both pressure and temperature",
     "offsets": (3, 2, 0, 0.0),
     "episodes": [
         {"start": 75, "length": 7, "heel": 7, "toe": 6, "temp": 1.4},
         {"start": 140, "length": 8, "heel": 7, "toe": 6, "temp": 1.5},
         {"start": 185, "length": 5, "heel": 6.5, "toe": 6, "temp": 1.4},
     ]},
]


def episode_boost(episode, i):
    """Fraction (0-1) of the episode's extra applied at reading i."""
    start, length = episode["start"], episode["length"]
    if not (start <= i < start + length):
        return 0.0
    if episode.get("ramp"):
        return (i - start + 1) / length
    return 1.0


def generate_nurse_shift(nurse, rng, nurse_number):
    off_heel, off_mid, off_toe, off_temp = nurse["offsets"]
    readings = []
    current_time = START_TIME

    for i in range(NUM_READINGS):
        # This nurse's normal: the usual ranges shifted by her offsets.
        heel = rng.uniform(35, 45) + off_heel
        midfoot = rng.uniform(15, 22) + off_mid
        toe = rng.uniform(25, 35) + off_toe
        temp = rng.uniform(32, 34) + off_temp
        motion = rng.choice(["standing", "walking", "sitting"])

        for ep in nurse["episodes"]:
            k = episode_boost(ep, i)
            if k:
                heel += ep.get("heel", 0) * k
                midfoot += ep.get("midfoot", 0) * k
                toe += ep.get("toe", 0) * k
                temp += ep.get("temp", 0) * k
                if ep.get("standing"):
                    motion = "standing"

        readings.append({
            "device_id": f"INSOLE-{nurse_number:03d}",
            "user_id": nurse["id"],
            "timestamp": current_time.isoformat(),
            "pressure": {
                "heel": round(heel, 1),
                "midfoot": round(midfoot, 1),
                "toe": round(toe, 1),
            },
            "temperature_celsius": round(temp, 1),
            "motion_state": motion,
            "battery_percent": max(20, 100 - (i // 5)),
        })
        current_time += timedelta(seconds=30)

    return readings


def generate_cohort():
    rng = random.Random(SEED)
    cohort = {}
    for n, nurse in enumerate(NURSES, start=1):
        cohort[nurse["id"]] = generate_nurse_shift(nurse, rng, n)
    return cohort


def classify_with_ml_module(cohort):
    """Run personalization.py on each nurse and print a summary table."""
    root = Path(__file__).parent.parent
    for folder in ("ml_personalisation", "ml_personalization"):
        if (root / folder / "personalization.py").exists():
            sys.path.insert(0, str(root / folder))
            break
    else:
        print("(ML folder not found, skipping the classification summary)")
        return

    from personalization import PersonalBaseline, RiskDetector

    print(f"\n{'Nurse':<9} {'Designed pattern':<17} normal caution alert")
    for nurse in NURSES:
        readings = cohort[nurse["id"]]
        base = PersonalBaseline.calibrate(nurse["id"], readings[:CALIBRATION_READINGS])
        det = RiskDetector(base)
        levels = [det.evaluate(r)["risk_level"] for r in readings[CALIBRATION_READINGS:]]
        print(f"{nurse['id']:<9} {nurse['category']:<17} "
              f"{levels.count('normal'):>6} {levels.count('caution'):>7} {levels.count('alert'):>5}")


if __name__ == "__main__":
    cohort = generate_cohort()
    out = Path(__file__).parent / "cohort_10_nurses.json"
    with open(out, "w") as f:
        json.dump(cohort, f, indent=2)
    total = sum(len(v) for v in cohort.values())
    print(f"Generated {total} readings for {len(cohort)} simulated nurses -> {out.name}")
    classify_with_ml_module(cohort)
