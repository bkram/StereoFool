#!/usr/bin/env python3
import argparse
import configparser
import subprocess
import sys
from pathlib import Path

from analyze_mpx import analyze


def _clamp(value, lo, hi):
    return max(lo, min(hi, value))


def _load_config(path):
    config = configparser.ConfigParser(interpolation=None)
    config.read(path)
    if "MPX" not in config:
        config["MPX"] = {}
    if "INTERFACES" not in config:
        config["INTERFACES"] = {}
    if "RDS" not in config:
        config["RDS"] = {}
    return config


def _save_config(config, path):
    with open(path, "w") as f:
        config.write(f)


def _set_calibration_defaults(config, enable_rds, processing_rate_hz):
    mpx = config["MPX"]
    interfaces = config["INTERFACES"]
    rds = config["RDS"]

    interfaces["source_mode"] = "tone"
    mpx["test_tone_mode"] = "mono"
    mpx["diff_level"] = "0.0"
    mpx["processing_rate_hz"] = str(processing_rate_hz)
    mpx["agc_enabled"] = "False"
    mpx["multiband_enabled"] = "False"
    mpx["preemphasis_limit_enabled"] = "False"
    mpx["composite_clip_enabled"] = "False"
    mpx["limit_mpx"] = "False"
    mpx["limit_lookahead_enabled"] = "False"
    mpx["output_gain_db"] = "0.0"
    mpx["input_gain_db"] = "0.0"
    mpx["en_rds"] = "True" if enable_rds else "False"
    if not enable_rds:
        rds["rds_level"] = "0.0"


def _run_capture(app_path, config_path, wav_path, length_s):
    cmd = [
        sys.executable,
        str(app_path),
        "--config",
        str(config_path),
        "--save-file",
        str(wav_path),
        "--length",
        str(length_s),
    ]
    return subprocess.run(cmd, check=False)


def main():
    parser = argparse.ArgumentParser(description="Auto-calibrate MPX output")
    parser.add_argument("--config", type=str, default="stereofool.ini")
    parser.add_argument("--wav", type=str, default="output.wav")
    parser.add_argument("--app", type=str, default="stereofool/app.py")
    parser.add_argument("--iterations", type=int, default=3)
    parser.add_argument("--length", type=float, default=10.0)
    parser.add_argument("--prepare", action="store_true", help="Apply calibration defaults")
    parser.add_argument("--no-prepare", dest="prepare", action="store_false")
    parser.set_defaults(prepare=True)
    parser.add_argument("--processing-rate", type=int, default=48000)
    parser.add_argument("--target-dev-khz", type=float, default=75.0)
    parser.add_argument("--target-pilot-pct", type=float, default=8.0)
    parser.add_argument("--target-rds-khz", type=float, default=2.0)
    parser.add_argument("--enable-rds", action="store_true")
    parser.add_argument("--tolerance-dev-khz", type=float, default=0.5)
    parser.add_argument("--tolerance-pilot-pct", type=float, default=0.5)
    parser.add_argument("--tolerance-rds-khz", type=float, default=0.2)
    args = parser.parse_args()

    config_path = Path(args.config)
    wav_path = Path(args.wav)
    app_path = Path(args.app)

    if not config_path.exists():
        print(f"Config not found: {config_path}", file=sys.stderr)
        return 2
    if not app_path.exists():
        print(f"App not found: {app_path}", file=sys.stderr)
        return 2

    target_pilot_khz = (args.target_pilot_pct / 100.0) * args.target_dev_khz

    for i in range(1, args.iterations + 1):
        config = _load_config(config_path)
        if args.prepare:
            _set_calibration_defaults(config, args.enable_rds, args.processing_rate)
        _save_config(config, config_path)

        result = _run_capture(app_path, config_path, wav_path, args.length)
        if result.returncode != 0:
            print("Capture failed; check device settings and logs.", file=sys.stderr)
            return result.returncode

        report = analyze(wav_path, nperseg=32768)
        peak_khz = report["peak"] * 75.0
        pilot_khz = report["pilot_rms"] * 75.0
        rds_khz = report["rds_rms"] * 75.0

        print(
            f"Iter {i}: peak {peak_khz:.2f} kHz, pilot {pilot_khz:.2f} kHz "
            f"({pilot_khz / args.target_dev_khz * 100.0:.2f}%), rds {rds_khz:.2f} kHz"
        )

        dev_ok = abs(peak_khz - args.target_dev_khz) <= args.tolerance_dev_khz
        pilot_ok = (
            abs((pilot_khz / args.target_dev_khz * 100.0) - args.target_pilot_pct)
            <= args.tolerance_pilot_pct
        )
        rds_ok = True
        if args.enable_rds:
            rds_ok = abs(rds_khz - args.target_rds_khz) <= args.tolerance_rds_khz
        if dev_ok and pilot_ok and rds_ok:
            print("Calibration within tolerance.")
            return 0

        # Update config for next iteration.
        mpx = config["MPX"]
        rds = config["RDS"]
        try:
            sum_level = float(mpx.get("sum_level", "1.0"))
        except ValueError:
            sum_level = 1.0
        try:
            pilot_level = float(mpx.get("pilot_level", "0.08"))
        except ValueError:
            pilot_level = 0.08
        try:
            rds_level = float(rds.get("rds_level", "2.0"))
        except ValueError:
            rds_level = 2.0

        if peak_khz > 1e-6:
            sum_level *= args.target_dev_khz / peak_khz
        sum_level = _clamp(sum_level, 0.1, 1.2)
        if pilot_khz > 1e-6:
            pilot_level *= target_pilot_khz / pilot_khz
        pilot_level = _clamp(pilot_level, 0.01, 0.2)
        if args.enable_rds and rds_khz > 1e-6:
            rds_level *= args.target_rds_khz / rds_khz
        rds_level = _clamp(rds_level, 0.1, 7.5)

        mpx["sum_level"] = f"{sum_level:.4f}"
        mpx["pilot_level"] = f"{pilot_level:.4f}"
        if args.enable_rds:
            rds["rds_level"] = f"{rds_level:.3f}"
        _save_config(config, config_path)

    print("Calibration iterations complete; check latest results.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
