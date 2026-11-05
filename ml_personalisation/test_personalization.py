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
    LiveScorer,
    process_reading,
    safety_check,
    MIN_CALIBRATION_READINGS,
    SAFETY_LIMITS,
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


class TestSafetyLimits(unittest.TestCase):
    def test_extreme_single_reading_is_always_an_alert(self):
        base = PersonalBaseline.calibrate("NURSE-A", normal_calibration())
        out = RiskDetector(base).evaluate(make_reading(heel=SAFETY_LIMITS["heel"] + 5))
        self.assertEqual(out["risk_level"], "alert")
        self.assertIn("safe limit", out["reason"])

    def test_baseline_learned_while_at_risk_still_alerts(self):
        # A nurse whose "normal" was learned at dangerously high values:
        # the personal baseline alone would call heel 90 normal.
        risky = normal_calibration(heel_shift=45)   # heel mean about 85
        base = PersonalBaseline.calibrate("NURSE-A", risky)
        out = RiskDetector(base).evaluate(make_reading(heel=88))
        self.assertEqual(out["risk_level"], "alert")

    def test_just_under_the_limit_is_not_a_safety_alert(self):
        base = PersonalBaseline.calibrate("NURSE-A", normal_calibration(heel_shift=25))
        out = RiskDetector(base).evaluate(make_reading(heel=SAFETY_LIMITS["heel"] - 1))
        self.assertNotIn("safe limit", out["reason"] or "")

    def test_safety_check_alone(self):
        self.assertEqual(safety_check(make_reading())["risk_level"], "normal")
        self.assertIsNone(safety_check(make_reading())["reason"])
        hot = safety_check(make_reading(temp=SAFETY_LIMITS["temperature"] + 0.5))
        self.assertEqual(hot["risk_level"], "alert")


class TestPlainWording(unittest.TestCase):
    def setUp(self):
        self.base = PersonalBaseline.calibrate("NURSE-A", normal_calibration())

    def detector(self):
        return RiskDetector(self.base, style="plain")

    def test_single_heel_wording(self):
        out = self.detector().evaluate(make_reading(heel=60))
        self.assertEqual(out["risk_level"], "caution")
        self.assertEqual(out["reason"], "Heel pressure is well above your usual.")

    def test_two_signals_wording_and_advice(self):
        out = self.detector().evaluate(make_reading(heel=60, temp=36))
        self.assertEqual(out["risk_level"], "alert")
        self.assertIn("Heel pressure and foot temperature are well above your usual.", out["reason"])
        self.assertIn("check your feet", out["reason"])

    def test_no_technical_jargon(self):
        out = self.detector().evaluate(make_reading(heel=60, temp=36))
        self.assertNotIn("SD", out["reason"])
        self.assertNotIn("baseline", out["reason"])

    def test_reason_only_names_the_zones_involved(self):
        # The app highlights a zone when its word appears in the reason.
        toe = self.detector().evaluate(make_reading(toe=48))["reason"].lower()
        self.assertIn("toe", toe)
        for other in ("heel", "midfoot", "temperature"):
            self.assertNotIn(other, toe)
        heel = self.detector().evaluate(make_reading(heel=60))["reason"].lower()
        for other in ("toe", "midfoot", "temperature"):
            self.assertNotIn(other, heel)

    def test_standing_note(self):
        d = self.detector()
        for _ in range(9):
            d.evaluate(make_reading(motion="standing"))
        out = d.evaluate(make_reading(heel=60, motion="standing"))
        self.assertIn("standing for about", out["reason"])

    def test_technical_style_unchanged(self):
        out = RiskDetector(self.base).evaluate(make_reading(heel=60))
        self.assertIn("SD above personal baseline", out["reason"])

    def test_levels_do_not_depend_on_style(self):
        for reading in (make_reading(), make_reading(heel=60), make_reading(heel=60, temp=36)):
            a = RiskDetector(self.base, style="technical").evaluate(reading)["risk_level"]
            b = RiskDetector(self.base, style="plain").evaluate(reading)["risk_level"]
            self.assertEqual(a, b)


class TestLiveScorer(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def scorer(self):
        return LiveScorer(baseline_dir=self.tmp.name, calibration_readings=60)

    def feed_calibration(self, scorer, user_id="NURSE-A", n=60):
        out = None
        for r in normal_calibration(n=n, user_id=user_id):
            out = scorer.process_reading(r)
        return out

    def test_learning_then_ready(self):
        sc = self.scorer()
        self.assertEqual(sc.status("NURSE-A")["state"], "learning")
        self.feed_calibration(sc, n=59)
        self.assertEqual(sc.status("NURSE-A"), {"state": "learning", "readings": 59, "needed": 60})
        self.feed_calibration(sc, n=1)
        self.assertEqual(sc.status("NURSE-A")["state"], "ready")
        self.assertTrue((Path(self.tmp.name) / "NURSE-A.json").exists())

    def test_learning_phase_reports_normal(self):
        out = self.feed_calibration(self.scorer(), n=30)
        self.assertEqual(out["risk_level"], "normal")
        self.assertIsNone(out["reason"])

    def test_dangerous_reading_alerts_even_while_learning(self):
        out = self.scorer().process_reading(make_reading(heel=95, user_id="NURSE-NEW"))
        self.assertEqual(out["risk_level"], "alert")

    def test_scores_after_calibration(self):
        sc = self.scorer()
        self.feed_calibration(sc)
        out = sc.process_reading(make_reading(heel=60, temp=36))
        self.assertEqual(out["risk_level"], "alert")
        self.assertEqual(set(out), {"user_id", "timestamp", "risk_level", "reason"})

    def test_baseline_survives_a_restart(self):
        first = self.scorer()
        self.feed_calibration(first)
        second = self.scorer()          # new object, same folder
        self.assertEqual(second.status("NURSE-A")["state"], "ready")
        out = second.process_reading(make_reading(heel=60, temp=36))
        self.assertEqual(out["risk_level"], "alert")

    def test_each_nurse_has_her_own_baseline(self):
        sc = self.scorer()
        self.feed_calibration(sc, user_id="NURSE-A")
        for r in normal_calibration(user_id="NURSE-B", heel_shift=25):
            sc.process_reading(r)
        reading = make_reading(heel=65, temp=35.5)
        a = sc.process_reading(dict(reading, user_id="NURSE-A"))
        b = sc.process_reading(dict(reading, user_id="NURSE-B"))
        self.assertEqual(a["risk_level"], "alert")
        self.assertNotEqual(b["risk_level"], "alert")

    def test_matches_batch_detector(self):
        readings = normal_calibration(n=60) + [make_reading(heel=60), make_reading(heel=60, temp=36),
                                               make_reading()]
        sc = self.scorer()
        live = [sc.process_reading(r) for r in readings][60:]
        base = PersonalBaseline.calibrate("NURSE-A", readings[:60])
        det = RiskDetector(base, style="plain")
        batch = [det.evaluate(r) for r in readings[60:]]
        self.assertEqual(live, batch)

    def test_reset_forgets_the_baseline(self):
        sc = self.scorer()
        self.feed_calibration(sc)
        sc.reset("NURSE-A")
        self.assertEqual(sc.status("NURSE-A")["state"], "learning")
        self.assertFalse((Path(self.tmp.name) / "NURSE-A.json").exists())

    def test_process_reading_function_with_own_scorer(self):
        sc = self.scorer()
        self.feed_calibration(sc)
        out = process_reading(make_reading(heel=60, temp=36), scorer=sc)
        self.assertEqual(out["risk_level"], "alert")



if __name__ == "__main__":
    unittest.main(verbosity=2)
