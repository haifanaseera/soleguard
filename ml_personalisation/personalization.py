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
# Reason wording has two styles:
#   "technical" - signal + how many SD above the personal baseline
#                 (good for analysis and the viva)
#   "plain"     - short sentences a nurse can read on the banner
# ============================================================

import json
import statistics
from pathlib import Path

SIGNALS = ("heel", "midfoot", "toe", "temperature")
PRESSURE_SIGNALS = ("heel", "midfoot", "toe")

# Minimum std per signal, so a very steady calibration period
# doesn't produce a near-zero std and absurd z-scores.
MIN_STD = {"heel": 1.0, "midfoot": 1.0, "toe": 1.0, "temperature": 0.2}

CAUTION_Z = 2.0   # 2 <= z < 3  -> caution
ALERT_Z = 3.0     # z >= 3      -> alert (if corroborated)

# Readings arrive every 30 s, so 10 readings = 5 minutes standing.
PROLONGED_STANDING_READINGS = 10

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
    """Flatten a contract-format reading into {signal_name: value}."""
    p = reading["pressure"]
    return {
        "heel": p["heel"],
        "midfoot": p["midfoot"],
        "toe": p["toe"],
        "temperature": reading["temperature_celsius"],
    }


def _compute_stats(signal_rows):
    """Mean + std per signal from a list of {signal: value} dicts."""
    stats = {}
    for s in SIGNALS:
        values = [row[s] for row in signal_rows]
        mean = statistics.mean(values)
        std = statistics.stdev(values) if len(values) > 1 else 0.0
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
    return {s: sig[s] for s in SIGNALS if sig[s] > SAFETY_LIMITS[s]}


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
                abs(row[s] - first_pass[s]["mean"]) / first_pass[s]["std"] < trim_z
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
    """

    def __init__(self, baseline, style="technical"):
        if style not in ("technical", "plain"):
            raise ValueError("style must be 'technical' or 'plain'")
        self.baseline = baseline
        self.style = style
        self.standing_streak = 0

    def z_scores(self, reading):
        sig = extract_signals(reading)
        return {
            s: (sig[s] - self.baseline.stats[s]["mean"]) / self.baseline.stats[s]["std"]
            for s in SIGNALS
        }

    def evaluate(self, reading):
        """Return the alert-output dict for one reading."""
        z = self.z_scores(reading)

        if reading["motion_state"] == "standing":
            self.standing_streak += 1
        else:
            self.standing_streak = 0
        prolonged = self.standing_streak >= PROLONGED_STANDING_READINGS

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
                minutes = self.standing_streak * 30 / 60
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
                minutes = self.standing_streak * 30 / 60
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
# Live scoring: one reading at a time
# ------------------------------------------------------------
class LiveScorer:
    """
    Scores readings as they arrive, one at a time, for any number of nurses.

    For each user_id it:
      1. loads a saved baseline from baseline_dir if one exists;
      2. otherwise collects the first `calibration_readings` readings,
         learns the baseline, and saves it for next time;
      3. then scores every reading against that baseline.

    While a baseline is still being learned, readings are reported as
    "normal" (reason None), EXCEPT readings above the safety limits, which
    are always alerts. Use status(user_id) to show "learning..." in the app.
    """

    def __init__(self, baseline_dir=None, style="plain",
                 calibration_readings=CALIBRATION_READINGS):
        self.baseline_dir = Path(baseline_dir) if baseline_dir else DEFAULT_BASELINE_DIR
        self.style = style
        self.calibration_readings = max(calibration_readings, MIN_CALIBRATION_READINGS)
        self._detectors = {}   # user_id -> RiskDetector
        self._buffers = {}     # user_id -> calibration readings so far

    def _baseline_path(self, user_id):
        return self.baseline_dir / f"{user_id}.json"

    def _detector(self, user_id):
        det = self._detectors.get(user_id)
        if det is None and self._baseline_path(user_id).exists():
            baseline = PersonalBaseline.load(self._baseline_path(user_id))
            det = RiskDetector(baseline, style=self.style)
            self._detectors[user_id] = det
        return det

    def status(self, user_id):
        """{'state': 'ready'|'learning', 'readings': n, 'needed': N}"""
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
        path = self._baseline_path(user_id)
        if path.exists():
            path.unlink()

    def process_reading(self, reading):
        """Return the alert dict (user_id, timestamp, risk_level, reason)."""
        user_id = reading["user_id"]
        detector = self._detector(user_id)
        if detector is not None:
            return detector.evaluate(reading)

        # Still learning this nurse's baseline.
        buffer = self._buffers.setdefault(user_id, [])
        buffer.append(reading)
        if len(buffer) >= self.calibration_readings:
            baseline = PersonalBaseline.calibrate(user_id, buffer)
            baseline.save(self._baseline_path(user_id))
            self._detectors[user_id] = RiskDetector(baseline, style=self.style)
            del self._buffers[user_id]
        return safety_check(reading, self.style)


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
