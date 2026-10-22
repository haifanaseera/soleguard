# ============================================================
# SoleGuard - Export the 10-nurse cohort for the mobile app
# ============================================================
# Takes the simulated 10-nurse cohort, runs the ML module on every
# nurse, and writes files the app can load, all in the locked
# data contract formats.
#
# Run from the repo root (after data/generate_cohort_data.py):
#     python ml_personalisation/export_app_demo.py
#
# Writes into data/app_demo/:
#   sample_shift_nurse01.json ... nurse10.json
#       Sensor readings (contract format), 30 s apart.
#   alerts_nurse01.json ... nurse10.json
#       ML alerts (contract format), ONE PER READING, same order and
#       timestamps as the sensor file. The first 60 readings are the
#       calibration phase (the module is still learning that nurse's
#       baseline), so they are "normal" with reason null.
#   nurses.json
#       Fictional profiles (name, age, gender, ward, health
#       conditions, simulated scenario) matching the Excel workbook.
#
# ALL DATA AND PROFILES ARE SIMULATED / FICTIONAL.
# ============================================================

import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
DATA_DIR = HERE.parent / "data"
OUT_DIR = DATA_DIR / "app_demo"
sys.path.insert(0, str(HERE))

from personalization import PersonalBaseline, RiskDetector

CALIBRATION_READINGS = 60  # first 30 minutes (60 x 30 s)

# id: (name, age, gender, ward, years nursing, diabetes type,
#      years with diabetes, foot sensation, other conditions, scenario)
PROFILES = {
    "NURSE-01": ("Anitha D'Souza", 34, "Female", "Medical ward", 9, "Type 2", 4, "Normal sensation", "None",
                 "Stable all shift, stays within own normal"),
    "NURSE-02": ("Rekha Shetty", 41, "Female", "Surgical ward", 15, "Type 2", 8, "Early loss of sensation", "Hypertension",
                 "Heel pressure rises after long standing; temperature normal"),
    "NURSE-03": ("Fathima Noor", 38, "Female", "ICU", 12, "Type 2", 6, "Normal sensation", "None",
                 "Foot temperature rises in short hot-spot episodes; pressure normal"),
    "NURSE-04": ("Savitha Rao", 49, "Female", "Operation theatre", 24, "Type 2", 12, "Confirmed neuropathy",
                 "Hypertension, high cholesterol", "Pressure and temperature both rise, repeatedly"),
    "NURSE-05": ("Joseph Pinto", 45, "Male", "Emergency", 20, "Type 2", 7, "Normal sensation", "Overweight",
                 "High readings by other nurses' standards, but normal and stable for this nurse"),
    "NURSE-06": ("Deepa Nayak", 36, "Female", "Paediatric ward", 11, "Type 1", 15, "Early loss of sensation", "None",
                 "Toe (forefoot) pressure rises, mostly while standing; temperature normal"),
    "NURSE-07": ("Lakshmi Bhat", 52, "Female", "ICU", 28, "Type 2", 14, "Confirmed neuropathy",
                 "Hypertension, varicose veins", "Long standing stretches with pressure and temperature rising together"),
    "NURSE-08": ("Mohammed Rafiq", 31, "Male", "Medical ward", 6, "Type 1", 3, "Normal sensation", "None",
                 "Stable all shift, stays within own normal"),
    "NURSE-09": ("Prema Kumari", 47, "Female", "Maternity ward", 22, "Type 2", 9, "Normal sensation", "Hypothyroidism",
                 "Foot temperature drifts upward through the second half of the shift; pressure normal"),
    "NURSE-10": ("Sunitha George", 43, "Female", "Surgical ward", 18, "Type 2", 10, "Early loss of sensation", "Hypertension",
                 "Mild rise in both pressure and temperature"),
}


def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    cohort_path = DATA_DIR / "cohort_10_nurses.json"
    if not cohort_path.exists():
        sys.exit("Missing data/cohort_10_nurses.json. Run  python data/generate_cohort_data.py  first.")
    with open(cohort_path) as f:
        cohort = json.load(f)

    OUT_DIR.mkdir(exist_ok=True)
    nurses = []

    print(f"{'Nurse':<9} {'Name':<16} normal caution alert")
    for user_id, readings in cohort.items():
        number = user_id.split("-")[1]
        baseline = PersonalBaseline.calibrate(user_id, readings[:CALIBRATION_READINGS])

        alerts = [
            {"user_id": r["user_id"], "timestamp": r["timestamp"], "risk_level": "normal", "reason": None}
            for r in readings[:CALIBRATION_READINGS]
        ]
        detector = RiskDetector(baseline)
        alerts += [detector.evaluate(r) for r in readings[CALIBRATION_READINGS:]]

        write_json(OUT_DIR / f"sample_shift_nurse{number}.json", readings)
        write_json(OUT_DIR / f"alerts_nurse{number}.json", alerts)

        name, age, gender, ward, yrs, dtype, dyrs, sensation, other, scenario = PROFILES[user_id]
        nurses.append({
            "user_id": user_id, "name": name, "age": age, "gender": gender, "ward": ward,
            "years_in_nursing": yrs, "diabetes_type": dtype, "years_with_diabetes": dyrs,
            "foot_sensation": sensation, "other_conditions": other,
            "device_id": readings[0]["device_id"], "scenario": scenario,
        })

        levels = [a["risk_level"] for a in alerts]
        print(f"{user_id:<9} {name:<16} {levels.count('normal'):>6} {levels.count('caution'):>7} {levels.count('alert'):>5}")

    write_json(OUT_DIR / "nurses.json", nurses)
    print(f"\nWrote 21 files into {OUT_DIR}")
