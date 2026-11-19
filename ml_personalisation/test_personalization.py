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
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from personalization import (
    PersonalBaseline,
    RiskDetector,
    LiveScorer,
    process_reading,
    safety_check,
    missing_signals,
    aggregate_windows,
    summarize_window,
    score_recording,
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



class TestMissingSensorValues(unittest.TestCase):
    """The firmware sends null for a signal when its sensor is unplugged."""

    def setUp(self):
        self.base = PersonalBaseline.calibrate("NURSE-A", normal_calibration())

    def test_missing_signals_helper(self):
        self.assertEqual(missing_signals(make_reading()), [])
        self.assertEqual(missing_signals(make_reading(temp=None)), ["temperature"])

    def test_normal_reading_with_null_temperature_is_normal(self):
        out = RiskDetector(self.base).evaluate(make_reading(temp=None))
        self.assertEqual(out["risk_level"], "normal")
        self.assertIsNone(out["reason"])

    def test_pressure_is_still_scored_without_temperature(self):
        out = RiskDetector(self.base, style="plain").evaluate(make_reading(heel=60, temp=None))
        self.assertEqual(out["risk_level"], "caution")      # one signal only
        self.assertEqual(out["reason"], "Heel pressure is well above your usual.")

    def test_two_pressure_zones_can_still_alert_without_temperature(self):
        out = RiskDetector(self.base).evaluate(make_reading(heel=60, toe=48, temp=None))
        self.assertEqual(out["risk_level"], "alert")

    def test_safety_limit_still_works_without_temperature(self):
        out = RiskDetector(self.base).evaluate(make_reading(heel=SAFETY_LIMITS["heel"] + 5, temp=None))
        self.assertEqual(out["risk_level"], "alert")

    def test_some_null_temperatures_during_calibration(self):
        readings = normal_calibration()
        for i in range(0, 60, 6):
            readings[i]["temperature_celsius"] = None
        base = PersonalBaseline.calibrate("NURSE-A", readings)
        self.assertIsNotNone(base.stats["temperature"])
        self.assertAlmostEqual(base.stats["temperature"]["mean"], 33, delta=0.5)

    def test_all_temperatures_null_during_calibration(self):
        readings = normal_calibration()
        for r in readings:
            r["temperature_celsius"] = None
        base = PersonalBaseline.calibrate("NURSE-A", readings)
        self.assertIsNone(base.stats["temperature"])
        self.assertIsNotNone(base.stats["heel"])
        # a later reading WITH a (below-limit) temperature is not scored on temperature
        out = RiskDetector(base).evaluate(make_reading(temp=36.0))
        self.assertEqual(out["risk_level"], "normal")
        # ...but the fixed safety limit still applies to it
        hot = RiskDetector(base).evaluate(make_reading(temp=SAFETY_LIMITS["temperature"] + 2))
        self.assertEqual(hot["risk_level"], "alert")

    def test_baseline_without_temperature_saves_and_loads(self):
        readings = normal_calibration()
        for r in readings:
            r["temperature_celsius"] = None
        base = PersonalBaseline.calibrate("NURSE-A", readings)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "NURSE-A.json"
            base.save(path)
            loaded = PersonalBaseline.load(path)
        self.assertIsNone(loaded.stats["temperature"])
        self.assertEqual(loaded.stats["heel"], base.stats["heel"])

    def test_live_scorer_handles_null_temperature(self):
        with tempfile.TemporaryDirectory() as tmp:
            sc = LiveScorer(baseline_dir=tmp, calibration_readings=60)
            for r in normal_calibration():
                sc.process_reading(dict(r, temperature_celsius=None))
            out = sc.process_reading(make_reading(heel=60, temp=None))
            self.assertEqual(out["risk_level"], "caution")


class TestMidfoot(unittest.TestCase):
    """Midfoot pressure is scored like heel and toe."""

    def setUp(self):
        self.base = PersonalBaseline.calibrate("NURSE-A", normal_calibration())

    def test_midfoot_alone_is_flagged_by_name(self):
        out = RiskDetector(self.base, style="plain").evaluate(make_reading(midfoot=28))
        self.assertEqual(out["risk_level"], "caution")
        self.assertEqual(out["reason"], "Midfoot pressure is well above your usual.")

    def test_midfoot_with_temperature_is_an_alert(self):
        out = RiskDetector(self.base, style="plain").evaluate(make_reading(midfoot=28, temp=36))
        self.assertEqual(out["risk_level"], "alert")
        self.assertIn("midfoot pressure", out["reason"].lower())

    def test_midfoot_reason_names_only_midfoot(self):
        reason = RiskDetector(self.base, style="plain").evaluate(make_reading(midfoot=28))["reason"].lower()
        for other in ("heel", "toe", "temperature"):
            self.assertNotIn(other, reason)



def stamped(readings, seconds_apart, start=datetime(2026, 10, 8, 7, 0, 0)):
    """Give readings real timestamps, seconds_apart seconds from each other."""
    out = []
    for i, r in enumerate(readings):
        out.append(dict(r, timestamp=(start + timedelta(seconds=i * seconds_apart)).isoformat()))
    return out


def one_hz_shift(normal_seconds=1800, raised_seconds=300, seed=3):
    """A 1-reading-per-second shift: normal, then heel/toe/temperature raised."""
    rng = random.Random(seed)
    readings = []
    for i in range(normal_seconds + raised_seconds):
        raised = i >= normal_seconds
        readings.append(make_reading(
            heel=rng.uniform(35, 45) + (14 if raised else 0),
            midfoot=rng.uniform(15, 22),
            toe=rng.uniform(25, 35) + (10 if raised else 0),
            temp=rng.uniform(32, 34) + (3 if raised else 0),
            motion="walking",
        ))
    return stamped(readings, 1)


class TestWindowing(unittest.TestCase):
    def test_one_summary_per_30_second_window(self):
        readings = stamped([make_reading() for _ in range(90)], 1)   # 90 s at 1 per second
        windows = aggregate_windows(readings, 30)
        self.assertEqual(len(windows), 3)
        self.assertTrue(all(w["readings_in_window"] == 30 for w in windows))

    def test_window_holds_the_mean(self):
        heels = list(range(30))                                   # 0..29, mean 14.5
        readings = stamped([make_reading(heel=h) for h in heels], 1)
        (window,) = aggregate_windows(readings, 30)
        self.assertAlmostEqual(window["pressure"]["heel"], 14.5)

    def test_window_timestamp_is_the_last_reading(self):
        readings = stamped([make_reading() for _ in range(30)], 1)
        (window,) = aggregate_windows(readings, 30)
        self.assertEqual(window["timestamp"], readings[-1]["timestamp"])

    def test_most_common_motion_state_wins_and_ties_go_to_the_latest(self):
        states = ["standing"] * 20 + ["walking"] * 10
        readings = stamped([make_reading(motion=m) for m in states], 1)
        self.assertEqual(summarize_window(readings)["motion_state"], "standing")
        tie = stamped([make_reading(motion=m) for m in ["standing"] * 5 + ["walking"] * 5], 1)
        self.assertEqual(summarize_window(tie)["motion_state"], "walking")

    def test_null_values_are_skipped_in_the_mean(self):
        temps = [None] * 10 + [34.0] * 20
        readings = stamped([make_reading(temp=t) for t in temps], 1)
        (window,) = aggregate_windows(readings, 30)
        self.assertAlmostEqual(window["temperature_celsius"], 34.0)

    def test_window_with_only_null_temperature_has_none(self):
        readings = stamped([make_reading(temp=None) for _ in range(30)], 1)
        (window,) = aggregate_windows(readings, 30)
        self.assertIsNone(window["temperature_celsius"])

    def test_readings_already_30_seconds_apart_are_unchanged(self):
        readings = stamped(normal_calibration(n=20), 30)
        windows = aggregate_windows(readings, 30)
        self.assertEqual(len(windows), 20)
        for r, w in zip(readings, windows):
            self.assertEqual(r["pressure"], w["pressure"])
            self.assertEqual(r["temperature_celsius"], w["temperature_celsius"])

    def test_missing_timestamp_is_a_clear_error(self):
        with self.assertRaises(ValueError):
            aggregate_windows([make_reading() | {"timestamp": None}], 30)


class TestWindowedScoring(unittest.TestCase):
    def test_one_hz_shift_raises_an_alert_soon_after_the_change(self):
        shift = one_hz_shift()
        with tempfile.TemporaryDirectory() as tmp:
            sc = LiveScorer(baseline_dir=tmp, window_seconds=30)
            alerts = [sc.process_reading(r) for r in shift]
            self.assertEqual(sc.status("NURSE-A")["state"], "ready")
        step = 1800
        before = alerts[1800 // 2:step]            # second half of the normal stretch
        self.assertTrue(all(a["risk_level"] != "alert" for a in before))
        first_alert = next(i for i, a in enumerate(alerts) if i >= step and a["risk_level"] == "alert")
        self.assertLess(first_alert - step, 70)    # within about one or two windows

    def test_alert_only_changes_when_a_window_completes(self):
        shift = one_hz_shift()
        with tempfile.TemporaryDirectory() as tmp:
            sc = LiveScorer(baseline_dir=tmp, window_seconds=30)
            levels = [sc.process_reading(r)["risk_level"] for r in shift]
        changes = sum(1 for a, b in zip(levels, levels[1:]) if a != b)
        windows = len(shift) // 30
        self.assertLessEqual(changes, windows)      # at most one change per window

    def test_alerts_carry_the_current_reading_timestamp(self):
        shift = one_hz_shift(normal_seconds=300, raised_seconds=0)
        with tempfile.TemporaryDirectory() as tmp:
            sc = LiveScorer(baseline_dir=tmp, window_seconds=30)
            for r in shift:
                self.assertEqual(sc.process_reading(r)["timestamp"], r["timestamp"])

    def test_flush_scores_the_last_window(self):
        shift = one_hz_shift(normal_seconds=1800, raised_seconds=20)
        with tempfile.TemporaryDirectory() as tmp:
            sc = LiveScorer(baseline_dir=tmp, window_seconds=30)
            for r in shift:
                sc.process_reading(r)
            last = sc.flush("NURSE-A")
        self.assertIsNotNone(last)
        self.assertIn(last["risk_level"], ("normal", "caution", "alert"))

    def test_score_recording_returns_one_alert_per_window(self):
        shift = one_hz_shift(normal_seconds=1800, raised_seconds=300)
        alerts = score_recording(shift, window_seconds=30)
        self.assertEqual(len(alerts), len(aggregate_windows(shift, 30)))
        self.assertTrue(any(a["risk_level"] == "alert" for a in alerts[60:]))
        self.assertTrue(all(a["risk_level"] == "normal" for a in alerts[:59]))

    def test_short_recording_can_use_fewer_learning_windows(self):
        shift = one_hz_shift(normal_seconds=600, raised_seconds=120)
        alerts = score_recording(shift, window_seconds=30, calibration_windows=10)
        self.assertTrue(any(a["risk_level"] == "alert" for a in alerts[10:]))

    def test_windowed_scoring_of_30_second_data_lags_one_reading(self):
        # A window is scored when the next one starts, so the alert for
        # reading k+1 is the alert unwindowed scoring gives reading k.
        data = stamped(normal_calibration(n=60) + [make_reading(heel=60, temp=36), make_reading(),
                                                   make_reading(heel=60, temp=36), make_reading()], 30)
        with tempfile.TemporaryDirectory() as t1, tempfile.TemporaryDirectory() as t2:
            plain = LiveScorer(baseline_dir=t1)
            windowed = LiveScorer(baseline_dir=t2, window_seconds=30)
            a = [plain.process_reading(r) for r in data]
            b = [windowed.process_reading(r) for r in data]
        key = lambda x: (x["risk_level"], x["reason"])
        self.assertEqual([key(x) for x in b[1:]], [key(x) for x in a[:-1]])

    def test_standing_rule_uses_the_sample_interval(self):
        base = PersonalBaseline.calibrate("NURSE-A", normal_calibration())
        det = RiskDetector(base, sample_seconds=10)       # 30 samples = 5 minutes
        for _ in range(29):
            det.evaluate(make_reading(motion="standing"))
        self.assertEqual(det.evaluate(make_reading(heel=60, motion="standing"))["risk_level"], "alert")
        det = RiskDetector(base, sample_seconds=10)
        for _ in range(28):
            det.evaluate(make_reading(motion="standing"))
        self.assertEqual(det.evaluate(make_reading(heel=60, motion="standing"))["risk_level"], "caution")



if __name__ == "__main__":
    unittest.main(verbosity=2)
