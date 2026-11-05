# ============================================================
# SoleGuard - ML demo (run this to test + show in the viva)
# ============================================================
# Run from the repo root:  python ml_personalization/demo.py
# ============================================================

import json
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).parent
DATA_DIR = HERE.parent / "data"
sys.path.insert(0, str(DATA_DIR))

from personalization import PersonalBaseline, RiskDetector
from generate_sample_data import generate_shift_data, sample_path

CALIBRATION_READINGS = 60  # first 30 minutes (60 x 30 s)


def load_or_generate(user_id):
    """Load data/sample_shift_nurseX.json if it exists, else generate it."""
    path = sample_path(user_id)
    if path.exists():
        with open(path) as f:
            return json.load(f)
    return generate_shift_data(user_id=user_id, num_readings=200)


def run_shift(readings):
    base = PersonalBaseline.calibrate(readings[0]["user_id"], readings[:CALIBRATION_READINGS])
    detector = RiskDetector(base)
    results = [detector.evaluate(r) for r in readings[CALIBRATION_READINGS:]]
    return base, results


if __name__ == "__main__":
    # ---------- 1. Full shift for NURSE-A ----------
    nurse_a = load_or_generate("NURSE-A")
    base_a, results = run_shift(nurse_a)

    print("=== NURSE-A: learned baseline ===")
    print(f"(used {base_a.n_used} of {base_a.n_total} calibration readings)")
    for s, v in base_a.stats.items():
        print(f"  {s:<12} mean={v['mean']:.2f}  std={v['std']:.2f}")

    counts = Counter(r["risk_level"] for r in results)
    print(f"\n=== NURSE-A: live phase ({len(results)} readings) ===")
    print(dict(counts))
    for r in [r for r in results if r["risk_level"] != "normal"][:3]:
        print(json.dumps(r, indent=2))

    base_a.save(HERE / "baselines" / "NURSE-A.json")

    # ---------- 2. Personalization proof ----------
    nurse_b = load_or_generate("NURSE-B")
    base_b, _ = run_shift(nurse_b)

    test = {
        "device_id": "INSOLE-001",
        "user_id": "TEST",
        "timestamp": "2026-09-24T14:32:00",
        "pressure": {"heel": 65.0, "midfoot": 18.0, "toe": 45.0},
        "temperature_celsius": 35.5,
        "motion_state": "walking",
        "battery_percent": 78,
    }

    print("\n=== PERSONALIZATION: same reading, two nurses ===")
    print("Reading: heel 65.0, toe 45.0, temp 35.5 C")
    for name, base in (("NURSE-A", base_a), ("NURSE-B", base_b)):
        t = dict(test, user_id=name)
        out = RiskDetector(base).evaluate(t)
        print(f"  {name}: {out['risk_level'].upper():<8} {out['reason']}")
