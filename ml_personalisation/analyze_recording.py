# ============================================================
# SoleGuard - Analyse a real insole recording
# ============================================================
# Reads a recording (a JSON list of readings in the data-contract
# format, ONE nurse/person), tells you what the data looks like, and
# scores it with the ML module using 30-second windows.
#
# Run from the repo root:
#     python ml_personalisation/analyze_recording.py data/soofi_recording.json
#
# Options:
#     --window 30        window length in seconds (default 30)
#     --calibration N    windows used to learn the baseline.
#                        Default: 60 (30 min), reduced automatically
#                        for short recordings (never below 10).
#     --technical        show SD numbers in the reasons
#
# It prints:
#   - how fast readings arrive, and how long the recording is
#   - min / median / max of each signal, and how many are null
#     (use this to check the pressure SCALE against the safety limits)
#   - the alerts per window
# and saves the alerts to <recording>_alerts.json next to the file.
# ============================================================

import argparse
import json
import statistics
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from personalization import (
    CALIBRATION_SECONDS,
    MIN_CALIBRATION_READINGS,
    SAFETY_LIMITS,
    SIGNALS,
    aggregate_windows,
    extract_signals,
    score_recording,
)


def load_recording(path):
    with open(path) as f:
        data = json.load(f)
    if isinstance(data, dict):  # e.g. {"NURSE-01": [...]}
        if len(data) != 1:
            sys.exit("The file holds several people. Give one person's readings as a list.")
        data = next(iter(data.values()))
    if not isinstance(data, list) or not data:
        sys.exit("Expected a JSON list of readings.")
    missing = [i for i, r in enumerate(data) if not r.get("timestamp")]
    if missing:
        sys.exit(f"{len(missing)} readings have no timestamp (first at position {missing[0]}). "
                 "Windowing needs a real timestamp on every reading.")
    return sorted(data, key=lambda r: r["timestamp"])


def describe(readings):
    times = [datetime.fromisoformat(r["timestamp"]) for r in readings]
    gaps = [(b - a).total_seconds() for a, b in zip(times, times[1:])]
    span = (times[-1] - times[0]).total_seconds()
    print(f"Readings        : {len(readings)}")
    print(f"Person(s)       : {sorted({r['user_id'] for r in readings})}")
    print(f"Length          : {span / 60:.1f} min")
    if gaps:
        median_gap = statistics.median(gaps)
        print(f"Typical gap     : {median_gap:.2f} s between readings (about {1 / median_gap:.2f} per second)"
              if median_gap > 0 else "Typical gap     : 0 s (repeated timestamps!)")
        if max(gaps) > 5 * max(median_gap, 1):
            print(f"  note: the longest gap is {max(gaps):.0f} s, so some readings may be missing")
    print()
    print(f"{'Signal':<13}{'min':>9}{'median':>9}{'max':>9}{'null':>7}   safety limit")
    for s in SIGNALS:
        values = [extract_signals(r)[s] for r in readings]
        real = [v for v in values if v is not None]
        nulls = len(values) - len(real)
        if real:
            print(f"{s:<13}{min(real):>9.1f}{statistics.median(real):>9.1f}{max(real):>9.1f}{nulls:>7}   "
                  f"{SAFETY_LIMITS[s]:.1f}")
        else:
            print(f"{s:<13}{'-':>9}{'-':>9}{'-':>9}{nulls:>7}   {SAFETY_LIMITS[s]:.1f}")
    print()
    print("Check the pressure columns against the safety limits: those limits assume the app's")
    print("scale. If your pressure values live on a different scale, the limits need changing.")
    print()


def main():
    parser = argparse.ArgumentParser(description="Analyse a real insole recording.")
    parser.add_argument("recording", help="JSON file with a list of readings")
    parser.add_argument("--window", type=int, default=30, help="window length in seconds")
    parser.add_argument("--calibration", type=int, default=None, help="windows used to learn the baseline")
    parser.add_argument("--technical", action="store_true", help="technical wording (SD numbers)")
    args = parser.parse_args()

    readings = load_recording(args.recording)
    describe(readings)

    windows = aggregate_windows(readings, args.window)
    default_calibration = round(CALIBRATION_SECONDS / args.window)
    calibration = args.calibration
    if calibration is None:
        calibration = min(default_calibration, max(MIN_CALIBRATION_READINGS, len(windows) // 3))
        if calibration < default_calibration:
            print(f"Short recording: learning the baseline from the first {calibration} windows "
                  f"({calibration * args.window / 60:.1f} min) instead of {default_calibration}.")
    if len(windows) <= calibration:
        sys.exit(f"Only {len(windows)} windows of {args.window} s: need more than {calibration} "
                 f"({calibration * args.window / 60:.1f} min) to learn a baseline and score anything.")

    alerts = score_recording(readings, window_seconds=args.window, calibration_windows=calibration,
                             style="technical" if args.technical else "plain")

    learning, live = alerts[:calibration], alerts[calibration:]
    counts = {lvl: sum(1 for a in live if a["risk_level"] == lvl) for lvl in ("normal", "caution", "alert")}
    print(f"\n{len(windows)} windows of {args.window} s: {calibration} to learn the baseline, "
          f"{len(live)} scored.")
    print(f"Scored windows: {counts['normal']} normal, {counts['caution']} caution, {counts['alert']} alert")
    unsafe = [a for a in learning if a["risk_level"] != "normal"]
    if unsafe:
        print(f"(+{len(unsafe)} windows during learning were above the safety limits)")

    print("\nFirst non-normal windows:")
    shown = 0
    for a in alerts:
        if a["risk_level"] != "normal":
            print(f"  {a['timestamp']}  {a['risk_level']:<8} {a['reason']}")
            shown += 1
            if shown == 8:
                break
    if shown == 0:
        print("  none")

    out = Path(args.recording).with_name(Path(args.recording).stem + "_alerts.json")
    with open(out, "w") as f:
        json.dump(alerts, f, indent=2)
    print(f"\nSaved {len(alerts)} alerts -> {out}")


if __name__ == "__main__":
    main()
