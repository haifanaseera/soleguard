# ============================================================
# SoleGuard - Personalized Baseline + Z-Score Risk Detection
# ============================================================
# Person C (Data/ML Lead)
#
# Three layers:
#   1. CALIBRATION - learn each user's OWN mean + standard
#      deviation per signal (heel, midfoot, toe, temperature)
#      from their first readings.
#   2. LIVE - compare every new reading against that user's
#      baseline using z-scores, and output a risk level.
#   3. SAFETY NET - fixed upper limits that always raise an alert,
#      whatever the baseline says (see SAFETY_LIMITS).
#
# Two ways to use it:
#   - Batch:  PersonalBaseline.calibrate() + RiskDetector.evaluate()
#   - Live:   process_reading(reading)  (one reading at a time; it
#             learns, saves and reloads each nurse's baseline itself)
#
# Input  : sensor reading dict (see docs/data-contract.md)
# Output : {user_id, timestamp, risk_level, reason}
#
# Reading rate: the rules below think in "samples" taken every 30 s
# (60 samples = 30 min of learning, 10 in a row = 5 min of standing).
# If the insole sends faster than that (it sends 1 per second), group the
# readings into 30-second windows first: LiveScorer(window_seconds=30) does
# it live, and score_recording() does it for a saved recording.
#
# Missing sensor values (for example the firmware sends null for
# temperature_celsius when the temperature sensor is unplugged) are
# allowed: that signal is simply skipped, and the remaining signals are
# still scored. Use missing_signals(reading) to see what is missing.
#
# Reason wording has two styles:
#   "technical" - signal + how many SD above the personal baseline
#                 (good for analysis and the viva)
#   "plain"     - short sentences a nurse can read on the banner
# ============================================================

import json
import math
import statistics
import tempfile
from collections import Counter
from datetime import datetime
from pathlib import Path

SIGNALS = ("heel", "midfoot", "toe", "temperature")
PRESSURE_SIGNALS = ("heel", "midfoot", "toe")

# Minimum std per signal, so a very steady calibration period
# doesn't produce a near-zero std and absurd z-scores.
MIN_STD = {"heel": 1.0, "midfoot": 1.0, "toe": 1.0, "temperature": 0.2}

CAUTION_Z = 2.0   # 2 <= z < 3  -> caution
ALERT_Z = 3.0     # z >= 3      -> alert (if corroborated)

# The rules assume one sample every SAMPLE_SECONDS, so 10 samples in a
# row = 5 minutes standing, and 60 samples = 30 minutes of learning.
SAMPLE_SECONDS = 30
PROLONGED_STANDING_SECONDS = 300
CALIBRATION_SECONDS = 1800
PROLONGED_STANDING_READINGS = 10   # = PROLONGED_STANDING_SECONDS / SAMPLE_SECONDS

MIN_CALIBRATION_READINGS = 10
CALIBRATION_READINGS = 60          # first 30 min (60 x 30 s)

# SAFETY NET: a reading ABOVE any of these limits is always an alert,
# even if it looks normal for this nurse (for example a baseline that
# was learned while the nurse was already at risk).
# PLACEHOLDER VALUES: they are the alert limits in the mobile app's
# demo rules (pressure in the sensor's units, temperature in deg C),
# not clinical values. Replace them with limits agreed with the guide.
SAFETY_LIMITS = {"heel": 80.0, "midfoot": 55.0, "toe": 65.0, "temperature": 37.5}

DEFAULT_BASELINE_DIR = Path(__file__).parent / "baselines"

# Technical wording (lower case, used in "technical" style)
LABELS = {
    "heel": "heel pressure",
    "midfoot": "midfoot pressure",
    "toe": "toe pressure",
    "temperature": "foot temperature",
}

# Plain wording (used in "plain" style). NOTE for the app: the mobile
# app highlights a zone when the reason text contains the word heel,
# midfoot, toe or temperature, so keep exactly one zone per label and
# never mention a zone in the advice sentences.
PLAIN_LABELS = {
    "heel": "Heel pressure",
    "midfoot": "Midfoot pressure",
    "toe": "Toe pressure",
    "temperature": "Foot temperature",
}

ALERT_ADVICE = "Take a short break and check your feet."


def extract_signals(reading):
    """
    Flatten a contract-format reading into {signal_name: value}.
    A value is None when the sensor sent null (or left the field out).
    """
    p = reading.get("pressure") or {}
    return {
        "heel": p.get("heel"),
        "midfoot": p.get("midfoot"),
        "toe": p.get("toe"),
        "temperature": reading.get("temperature_celsius"),
    }


def missing_signals(reading):
    """Names of signals that are null/missing in this reading (e.g. ['temperature'])."""
    return [s for s, v in extract_signals(reading).items() if v is None]


def _compute_stats(signal_rows):
    """
    Mean + std per signal from a list of {signal: value} dicts.
    Missing (None) values are skipped. A signal with fewer than
    MIN_CALIBRATION_READINGS real values gets None (no baseline for it,
    so it is not scored).
    """
    stats = {}
    for s in SIGNALS:
        values = [row[s] for row in signal_rows if row[s] is not None]
        if len(values) < MIN_CALIBRATION_READINGS:
            stats[s] = None
            continue
        mean = statistics.mean(values)
        std = statistics.stdev(values)
        stats[s] = {"mean": mean, "std": max(std, MIN_STD[s])}
    return stats


# ------------------------------------------------------------
# Wording helpers
# ------------------------------------------------------------
def _join_names(labels):
    """['Heel pressure', 'Foot temperature'] -> 'Heel pressure and foot temperature'."""
    names = [labels[0]] + [l[0].lower() + l[1:] for l in labels[1:]]
    if len(names) == 1:
        return names[0]
    return ", ".join(names[:-1]) + " and " + names[-1]


def _plain_sentence(signals, phrase):
    names = _join_names([PLAIN_LABELS[s] for s in signals])
    verb = "is" if len(signals) == 1 else "are"
    return f"{names} {verb} {phrase}."


def _format_value(signal, value):
    return f"{value:.1f} °C" if signal == "temperature" else f"{value:.1f}"


# ------------------------------------------------------------
# Safety net
# ------------------------------------------------------------
def safety_findings(reading):
    """Signals above their absolute safety limit: {signal: value}."""
    sig = extract_signals(reading)
    return {s: sig[s] for s in SIGNALS if sig[s] is not None and sig[s] > SAFETY_LIMITS[s]}


def _safety_parts(findings, style):
    parts = []
    for s, value in findings.items():
        if style == "plain":
            parts.append(
                f"{PLAIN_LABELS[s]} is very high ({_format_value(s, value)}), "
                f"above the safe limit."
            )
        else:
            parts.append(
                f"{LABELS[s]} {_format_value(s, value)} above safe limit "
                f"{_format_value(s, SAFETY_LIMITS[s])}"
            )
    return parts


def _join_reason(parts, style):
    return " ".join(parts) if style == "plain" else "; ".join(parts)


def safety_check(reading, style="plain"):
    """
    Alert dict using ONLY the safety limits. Used while a nurse's baseline
    is still being learned, so a dangerous reading is never missed.
    """
    findings = safety_findings(reading)
    if not findings:
        level, reason = "normal", None
    else:
        parts = _safety_parts(findings, style)
        if style == "plain":
            parts.append(ALERT_ADVICE)
        level, reason = "alert", _join_reason(parts, style)
    return {
        "user_id": reading["user_id"],
        "timestamp": reading["timestamp"],
        "risk_level": level,
        "reason": reason,
    }


# ------------------------------------------------------------
# Baseline
# ------------------------------------------------------------
class PersonalBaseline:
    """One user's learned 'normal' (mean + std per signal)."""

    def __init__(self, user_id, stats, n_used, n_total):
        self.user_id = user_id
        self.stats = stats
        self.n_used = n_used      # readings kept after outlier trimming
        self.n_total = n_total    # readings supplied for calibration

    @classmethod
    def calibrate(cls, user_id, readings, trim_z=3.0):
        """
        Learn a baseline from calibration-phase readings.

        Two passes: the first pass gives rough stats; readings far
        outside them (|z| >= trim_z, e.g. a spike during calibration)
        are dropped and the stats are recomputed. This stops a few
        abnormal readings from inflating the user's "normal".
        """
        if len(readings) < MIN_CALIBRATION_READINGS:
            raise ValueError(
                f"Need at least {MIN_CALIBRATION_READINGS} readings to "
                f"calibrate, got {len(readings)}"
            )

        rows = [extract_signals(r) for r in readings]
        first_pass = _compute_stats(rows)

        clean = [
            row for row in rows
            if all(
                first_pass[s] is None
                or row[s] is None
                or abs(row[s] - first_pass[s]["mean"]) / first_pass[s]["std"] < trim_z
                for s in SIGNALS
            )
        ]
        if len(clean) < MIN_CALIBRATION_READINGS:
            clean = rows  # trimming removed too much; fall back

        return cls(user_id, _compute_stats(clean), len(clean), len(rows))

    # ---- persistence (the "stored baseline" box in the architecture) ----
    def save(self, path):
        data = {
            "user_id": self.user_id,
            "n_used": self.n_used,
            "n_total": self.n_total,
            "stats": self.stats,
        }
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as f:
            json.dump(data, f, indent=2)

    @classmethod
    def load(cls, path):
        with open(path) as f:
            d = json.load(f)
        return cls(d["user_id"], d["stats"], d["n_used"], d["n_total"])


# ------------------------------------------------------------
# Detector
# ------------------------------------------------------------
class RiskDetector:
    """
    Live phase. Create one per user and feed readings in order
    (it tracks how long the user has been standing).

    style: "technical" (default, SD values) or "plain" (nurse-friendly).
    sample_seconds: seconds between the readings you feed in (30 by
    default). It only sets how many in a row count as 5 minutes of
    standing, and the "standing for about N min" text.
    """

    def __init__(self, baseline, style="technical", sample_seconds=SAMPLE_SECONDS):
        if style not in ("technical", "plain"):
            raise ValueError("style must be 'technical' or 'plain'")
        self.baseline = baseline
        self.style = style
        self.sample_seconds = sample_seconds
        self.prolonged_after = max(1, math.ceil(PROLONGED_STANDING_SECONDS / sample_seconds))
        self.standing_streak = 0

    def z_scores(self, reading):
        sig = extract_signals(reading)
        return {
            s: (sig[s] - self.baseline.stats[s]["mean"]) / self.baseline.stats[s]["std"]
            for s in SIGNALS
            if sig[s] is not None and self.baseline.stats.get(s) is not None
        }

    def evaluate(self, reading):
        """Return the alert-output dict for one reading."""
        z = self.z_scores(reading)

        if reading["motion_state"] == "standing":
            self.standing_streak += 1
        else:
            self.standing_streak = 0
        prolonged = self.standing_streak >= self.prolonged_after

        # Only HIGH readings are risky (high pressure / high temperature).
        elevated = {s: v for s, v in z.items() if v >= CAUTION_Z}
        safety = safety_findings(reading)

        personal_level = "normal"
        pressure_elevated = any(s in PRESSURE_SIGNALS for s in elevated)
        if elevated:
            top = max(elevated.values())
            # Multi-signal rule: a single signal alone never triggers an
            # alert. Needs a second elevated signal, or high pressure
            # combined with prolonged standing.
            corroborated = len(elevated) >= 2 or (prolonged and pressure_elevated)
            personal_level = "alert" if (top >= ALERT_Z and corroborated) else "caution"

        # The safety net can only raise the level, never lower it.
        level = "alert" if safety else personal_level

        if level == "normal":
            reason = None
        elif self.style == "technical":
            parts = _safety_parts(safety, "technical")
            parts += [
                f"{LABELS[s]} {v:.1f} SD above personal baseline"
                for s, v in sorted(elevated.items(), key=lambda kv: -kv[1])
            ]
            if elevated and prolonged and pressure_elevated:
                minutes = self.standing_streak * self.sample_seconds / 60
                parts.append(f"standing for ~{minutes:.0f} min")
            reason = _join_reason(parts, "technical")
        else:
            parts = _safety_parts(safety, "plain")
            rest = {s: v for s, v in elevated.items() if s not in safety}
            strong = [s for s, v in sorted(rest.items(), key=lambda kv: -kv[1]) if v >= ALERT_Z]
            mild = [s for s, v in sorted(rest.items(), key=lambda kv: -kv[1]) if v < ALERT_Z]
            if strong:
                parts.append(_plain_sentence(strong, "well above your usual"))
            if mild:
                parts.append(_plain_sentence(mild, "above your usual"))
            if elevated and prolonged and pressure_elevated:
                minutes = self.standing_streak * self.sample_seconds / 60
                parts.append(f"You have been standing for about {minutes:.0f} min.")
            if level == "alert":
                parts.append(ALERT_ADVICE)
            reason = _join_reason(parts, "plain")

        return {
            "user_id": reading["user_id"],
            "timestamp": reading["timestamp"],
            "risk_level": level,
            "reason": reason,
        }


# ------------------------------------------------------------
# 30-second windows (for readings that arrive faster than every 30 s)
# ------------------------------------------------------------
def _window_id(reading, window_seconds):
    """Which fixed time window (aligned to the clock) this reading falls in."""
    ts = reading.get("timestamp")
    if ts is None:
        raise ValueError("Windowing needs a timestamp on every reading")
    return math.floor(datetime.fromisoformat(ts).timestamp() / window_seconds)


def summarize_window(readings):
    """
    One reading that stands for several: the mean of each signal (ignoring
    null values; None if every value was null), the most common motion
    state (a tie goes to the most recent), and the last timestamp.
    """
    def mean_of(values):
        values = [v for v in values if v is not None]
        if not values:
            return None
        return values[0] if len(values) == 1 else statistics.mean(values)

    signals = [extract_signals(r) for r in readings]
    counts = Counter(r.get("motion_state") for r in readings)
    top = max(counts.values())
    motion = next(r.get("motion_state") for r in reversed(readings)
                  if counts[r.get("motion_state")] == top)
    last = readings[-1]
    return {
        "device_id": last.get("device_id"),
        "user_id": last["user_id"],
        "timestamp": last["timestamp"],
        "pressure": {s: mean_of([x[s] for x in signals]) for s in PRESSURE_SIGNALS},
        "temperature_celsius": mean_of([x["temperature"] for x in signals]),
        "motion_state": motion,
        "battery_percent": last.get("battery_percent"),
        "readings_in_window": len(readings),
    }


def aggregate_windows(readings, window_seconds=SAMPLE_SECONDS):
    """
    Group one nurse's readings (in time order) into fixed windows and
    return one summary reading per window. Readings that are already
    window_seconds apart (or slower) come back as they are.
    """
    windows, current, current_id = [], [], None
    for r in readings:
        wid = _window_id(r, window_seconds)
        if current and wid != current_id:
            windows.append(summarize_window(current))
            current = []
        current_id = wid
        current.append(r)
    if current:
        windows.append(summarize_window(current))
    return windows


# ------------------------------------------------------------
# Live scoring: one reading at a time
# ------------------------------------------------------------
class LiveScorer:
    """
    Scores readings as they arrive, one at a time, for any number of nurses.

    For each user_id it:
      1. loads a saved baseline from baseline_dir if one exists;
      2. otherwise collects the first `calibration_readings` samples,
         learns the baseline, and saves it for next time;
      3. then scores every sample against that baseline.

    While a baseline is still being learned, samples are reported as
    "normal" (reason None), EXCEPT samples above the safety limits, which
    are always alerts. Use status(user_id) to show "learning..." in the app.

    window_seconds=None (default): every reading is one sample, so readings
    should arrive about every 30 s (what the recorded shifts use).

    window_seconds=30: readings can arrive as fast as you like (the insole
    sends 1 per second). They are grouped into 30-second windows and the
    window average is what gets scored. A window is scored when the next
    one starts, so process_reading() returns the alert of the last
    COMPLETED window, stamped with the current reading's timestamp. It
    changes at most every 30 s, which keeps the banner from flickering.
    Call flush(user_id) at the end of a recording to score the last window.
    """

    def __init__(self, baseline_dir=None, style="plain", calibration_readings=None,
                 window_seconds=None, sample_seconds=None):
        self.baseline_dir = Path(baseline_dir) if baseline_dir else DEFAULT_BASELINE_DIR
        self.style = style
        self.window_seconds = window_seconds
        self.sample_seconds = sample_seconds or window_seconds or SAMPLE_SECONDS
        if calibration_readings is None:
            calibration_readings = round(CALIBRATION_SECONDS / self.sample_seconds)
        self.calibration_readings = max(calibration_readings, MIN_CALIBRATION_READINGS)
        self._detectors = {}   # user_id -> RiskDetector
        self._buffers = {}     # user_id -> calibration samples so far
        self._windows = {}     # user_id -> {"id", "readings", "alert"}

    def _baseline_path(self, user_id):
        return self.baseline_dir / f"{user_id}.json"

    def _make_detector(self, baseline):
        return RiskDetector(baseline, style=self.style, sample_seconds=self.sample_seconds)

    def _detector(self, user_id):
        det = self._detectors.get(user_id)
        if det is None and self._baseline_path(user_id).exists():
            baseline = PersonalBaseline.load(self._baseline_path(user_id))
            det = self._make_detector(baseline)
            self._detectors[user_id] = det
        return det

    def status(self, user_id):
        """{'state': 'ready'|'learning', 'readings': n, 'needed': N} (counts samples/windows)"""
        if self._detector(user_id) is not None:
            return {"state": "ready", "readings": self.calibration_readings,
                    "needed": self.calibration_readings}
        return {"state": "learning",
                "readings": len(self._buffers.get(user_id, [])),
                "needed": self.calibration_readings}

    def reset(self, user_id):
        """Forget this nurse's baseline so it is learned again."""
        self._detectors.pop(user_id, None)
        self._buffers.pop(user_id, None)
        self._windows.pop(user_id, None)
        path = self._baseline_path(user_id)
        if path.exists():
            path.unlink()

    def _score_sample(self, sample):
        """Learn from / score ONE sample (a reading, or a window summary)."""
        user_id = sample["user_id"]
        detector = self._detector(user_id)
        if detector is not None:
            return detector.evaluate(sample)

        # Still learning this nurse's baseline.
        buffer = self._buffers.setdefault(user_id, [])
        buffer.append(sample)
        if len(buffer) >= self.calibration_readings:
            baseline = PersonalBaseline.calibrate(user_id, buffer)
            baseline.save(self._baseline_path(user_id))
            self._detectors[user_id] = self._make_detector(baseline)
            del self._buffers[user_id]
        return safety_check(sample, self.style)

    def _finish_window(self, user_id):
        w = self._windows.get(user_id)
        if not w or not w["readings"]:
            return None
        w["alert"] = self._score_sample(summarize_window(w["readings"]))
        w["readings"] = []
        w["id"] = None
        return w["alert"]

    def flush(self, user_id):
        """Score the window still being filled (use at the end of a recording)."""
        return self._finish_window(user_id)

    def process_reading(self, reading):
        """Return the alert dict (user_id, timestamp, risk_level, reason)."""
        if self.window_seconds is None:
            return self._score_sample(reading)

        user_id = reading["user_id"]
        w = self._windows.setdefault(user_id, {"id": None, "readings": [], "alert": None})
        wid = _window_id(reading, self.window_seconds)
        if w["id"] is not None and wid != w["id"]:
            self._finish_window(user_id)
        w["id"] = wid
        w["readings"].append(reading)

        alert = w["alert"]
        return {
            "user_id": user_id,
            "timestamp": reading["timestamp"],
            "risk_level": alert["risk_level"] if alert else "normal",
            "reason": alert["reason"] if alert else None,
        }


def score_recording(readings, window_seconds=SAMPLE_SECONDS, calibration_windows=None,
                    style="plain"):
    """
    Score a saved recording of ONE nurse (readings in time order, any rate).
    The readings are grouped into windows; the first `calibration_windows`
    windows teach the baseline (default 60 = 30 min with 30 s windows).
    Returns one alert per window; each alert is stamped with the window's
    last timestamp. Nothing is saved to disk.
    """
    if len({r["user_id"] for r in readings}) > 1:
        raise ValueError("score_recording takes one nurse at a time")
    samples = aggregate_windows(readings, window_seconds)
    with tempfile.TemporaryDirectory() as tmp:
        scorer = LiveScorer(baseline_dir=tmp, style=style,
                            calibration_readings=calibration_windows,
                            sample_seconds=window_seconds)
        return [scorer.process_reading(sample) for sample in samples]


_default_scorer = None


def process_reading(reading, scorer=None):
    """
    Score ONE live reading and return its alert dict.

        from personalization import process_reading
        alert = process_reading(reading)

    Uses a shared LiveScorer (plain wording, baselines saved in the
    'baselines' folder next to this file). Pass your own LiveScorer to
    change the folder or style.
    """
    global _default_scorer
    if scorer is None:
        if _default_scorer is None:
            _default_scorer = LiveScorer()
        scorer = _default_scorer
    return scorer.process_reading(reading)
