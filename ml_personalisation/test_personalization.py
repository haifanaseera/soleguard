# ============================================================
# SoleGuard - Tests for personalization.py
# ============================================================
# Run from the repo root:
#     python -m unittest ml_personalization/test_personalization.py -v
# (or just: python ml_personalization/test_personalization.py)
# Uses Python's built-in unittest, nothing to install.
# ============================================================

import random
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from personalization import (
    PersonalBaseline,
    RiskDetector,
    MIN_CALIBRATION_READINGS,
)


def make_reading(heel=40.0, midfoot=18.5, toe=30.0, temp=33.0,
                 motion="walking", user_id="NURSE-A"):
    return {
        "device_id": "INSOLE-001",
        "user_id": user_id,
        "timestamp": "2026-09-24T14:32:00",
        "pressure": {"heel": heel, "midfoot": midfoot, "toe": toe},
        "temperature_celsius": temp,
        "motion_state": motion,
        "battery_percent": 78,
    }


def normal_calibration(n=60, seed=42, user_id="NURSE-A", heel_shift=0.0):
    """n normal-looking readings with a bit of random variation."""
    rng = random.Random(seed)
    return [
        make_reading(
            heel=rng.uniform(35, 45) + heel_shift,
            midfoot=rng.uniform(15, 22),
            toe=rng.uniform(25, 35),
            temp=rng.uniform(32, 34),
            user_id=user_id,
        )
        for _ in range(n)
    ]


class TestCalibration(unittest.TestCase):
    def test_needs_minimum_readings(self):
        few = normal_calibration(n=MIN_CALIBRATION_READINGS - 1)
        with self.assertRaises(ValueError):
            PersonalBaseline.calibrate("NURSE-A", few)

    def test_learns_sensible_mean(self):
        base = PersonalBaseline.calibrate("NURSE-A", normal_calibration())
        self.assertAlmostEqual(base.stats["heel"]["mean"], 40, delta=2)
        self.assertAlmostEqual(base.stats["temperature"]["mean"], 33, delta=0.5)

    def test_outliers_in_calibration_are_trimmed(self):
        clean = normal_calibration()
        spiky = clean + [make_reading(heel=90, toe=80, temp=38, motion="standing")] * 3
        base = PersonalBaseline.calibrate("NURSE-A", spiky)
        self.assertLess(base.n_used, base.n_total)           # spikes dropped
        self.assertAlmostEqual(base.stats["heel"]["mean"], 40, delta=2)

    def test_save_and_load_roundtrip(self):
        base = PersonalBaseline.calibrate("NURSE-A", normal_calibration())
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "NURSE-A.json"
            base.save(path)
            loaded = PersonalBaseline.load(path)
        self.assertEqual(loaded.user_id, "NURSE-A")
        self.assertEqual(loaded.stats, base.stats)


class TestRiskLevels(unittest.TestCase):
    def setUp(self):
        self.base = PersonalBaseline.calibrate("NURSE-A", normal_calibration())
        self.detector = RiskDetector(self.base)

    def test_output_matches_data_contract(self):
        out = self.detector.evaluate(make_reading())
        self.assertEqual(set(out), {"user_id", "timestamp", "risk_level", "reason"})

    def test_normal_reading(self):
        out = self.detector.evaluate(make_reading())
        self.assertEqual(out["risk_level"], "normal")
        self.assertIsNone(out["reason"])

    def test_single_signal_spike_is_only_caution(self):
        # Only heel is far above baseline -> not corroborated -> caution
        out = self.detector.evaluate(make_reading(heel=60))
        self.assertEqual(out["risk_level"], "caution")
        self.assertIn("heel pressure", out["reason"])

    def test_two_signals_elevated_is_alert(self):
        out = self.detector.evaluate(make_reading(heel=60, temp=36))
        self.assertEqual(out["risk_level"], "alert")
        self.assertIn("foot temperature", out["reason"])

    def test_moderate_elevation_is_caution(self):
        # Just above 2 SD on heel only
        mean = self.base.stats["heel"]["mean"]
        std = self.base.stats["heel"]["std"]
        out = self.detector.evaluate(make_reading(heel=mean + 2.5 * std))
        self.assertEqual(out["risk_level"], "caution")

    def test_low_values_are_not_flagged(self):
        out = self.detector.evaluate(make_reading(heel=5, temp=30))
        self.assertEqual(out["risk_level"], "normal")


class TestProlongedStanding(unittest.TestCase):
    def setUp(self):
        self.base = PersonalBaseline.calibrate("NURSE-A", normal_calibration())

    def test_high_pressure_after_long_standing_is_alert(self):
        detector = RiskDetector(self.base)
        for _ in range(9):
            detector.evaluate(make_reading(motion="standing"))
        out = detector.evaluate(make_reading(heel=60, motion="standing"))  # 10th
        self.assertEqual(out["risk_level"], "alert")
        self.assertIn("standing", out["reason"])

    def test_same_pressure_without_long_standing_is_caution(self):
        detector = RiskDetector(self.base)
        out = detector.evaluate(make_reading(heel=60, motion="standing"))
        self.assertEqual(out["risk_level"], "caution")

    def test_standing_streak_resets_when_user_moves(self):
        detector = RiskDetector(self.base)
        for _ in range(9):
            detector.evaluate(make_reading(motion="standing"))
        detector.evaluate(make_reading(motion="walking"))   # resets streak
        out = detector.evaluate(make_reading(heel=60, motion="standing"))
        self.assertEqual(out["risk_level"], "caution")


class TestPersonalization(unittest.TestCase):
    def test_same_reading_different_verdict_per_user(self):
        base_a = PersonalBaseline.calibrate("NURSE-A", normal_calibration())
        base_b = PersonalBaseline.calibrate(
            "NURSE-B", normal_calibration(user_id="NURSE-B", heel_shift=25)
        )
        reading = make_reading(heel=65, temp=35.5)

        out_a = RiskDetector(base_a).evaluate(dict(reading, user_id="NURSE-A"))
        out_b = RiskDetector(base_b).evaluate(dict(reading, user_id="NURSE-B"))

        self.assertEqual(out_a["risk_level"], "alert")
        self.assertNotEqual(out_b["risk_level"], "alert")


if __name__ == "__main__":
    unittest.main(verbosity=2)
