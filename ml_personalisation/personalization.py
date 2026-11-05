# ============================================================
# SoleGuard - Personalized Baseline + Z-Score Risk Detection
# ============================================================
# Person C (Data/ML Lead)
#
# Two phases:
#   1. CALIBRATION - learn each user's OWN mean + standard
#      deviation per signal (heel, midfoot, toe, temperature)
#      from their first readings.
#   2. LIVE - compare every new reading against that user's
#      baseline using z-scores, and output a risk level.
#
# Input  : sensor reading dict (see docs/data-contract.md)
# Output : {user_id, timestamp, risk_level, reason}
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

LABELS = {
    "heel": "heel pressure",
    "midfoot": "midfoot pressure",
    "toe": "toe pressure",
    "temperature": "foot temperature",
}


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


class RiskDetector:
    """
    Live phase. Create one per user and feed readings in order
    (it tracks how long the user has been standing).
    """

    def __init__(self, baseline):
        self.baseline = baseline
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

        if not elevated:
            level, reason = "normal", None
        else:
            top = max(elevated.values())
            pressure_elevated = any(s in PRESSURE_SIGNALS for s in elevated)

            # Multi-signal rule: a single signal alone never triggers an
            # alert. Needs a second elevated signal, or high pressure
            # combined with prolonged standing.
            corroborated = len(elevated) >= 2 or (prolonged and pressure_elevated)

            level = "alert" if (top >= ALERT_Z and corroborated) else "caution"

            parts = [
                f"{LABELS[s]} {v:.1f} SD above personal baseline"
                for s, v in sorted(elevated.items(), key=lambda kv: -kv[1])
            ]
            if prolonged and pressure_elevated:
                minutes = self.standing_streak * 30 / 60
                parts.append(f"standing for ~{minutes:.0f} min")
            reason = "; ".join(parts)

        return {
            "user_id": reading["user_id"],
            "timestamp": reading["timestamp"],
            "risk_level": level,
            "reason": reason,
        }
