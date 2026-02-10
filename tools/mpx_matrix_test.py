#!/usr/bin/env python3
import argparse
import configparser
import itertools
import json
import math
import os
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.append(os.path.dirname(os.path.dirname(__file__)))

import numpy as np
from scipy import signal as dsp_signal

from stereofool.audio import FMEngine
from stereofool.constants import BLOCKSIZE, DEFAULT_SAMPLE_RATE, RDS_FREQ
from stereofool.state import mpx_state, rds_default_state, rds_state

from analyze_mpx import _bandpass_stats, _dbfs, _plot_spectrum, analyze_array


TOGGLES = [
    "agc_enabled",
    "multiband_enabled",
    "preemphasis_limit_enabled",
    "composite_clip_enabled",
    "limit_mpx",
    "limit_lookahead_enabled",
    "mpx_lpf_enabled",
]

# Spec sources: ITU-R BS.450-4 (pilot/M/S limits), EN 50067 (RDS deviation/frequency).
MAX_DEVIATION_KHZ = 75.0
PILOT_MIN = 0.08
PILOT_MAX = 0.10
BASEBAND_MAX = 0.90
STEREO_MAX = 0.90
COMPOSITE_MAX = 1.01
BASEBAND_TOL = 0.03
STEREO_TOL = 0.03
RDS_DEV_MIN_KHZ = 1.0
RDS_DEV_MAX_KHZ = 7.5
RDS_FREQ_HZ = 57000.0
RDS_FREQ_TOL_HZ = 6.0
PILOT_RMS_MIN = PILOT_MIN / math.sqrt(2.0)
PILOT_RMS_MAX = PILOT_MAX / math.sqrt(2.0)


def _reset_state(base_mpx, base_rds):
    mpx_state.clear()
    mpx_state.update(base_mpx)
    rds_state.clear()
    rds_state.update(base_rds)


def _coerce_value(raw, base_value):
    if isinstance(base_value, bool):
        return str(raw).strip().lower() in ("1", "true", "yes", "on")
    if isinstance(base_value, int) and not isinstance(base_value, bool):
        try:
            return int(str(raw).strip())
        except ValueError:
            return base_value
    if isinstance(base_value, float):
        try:
            return float(str(raw).strip())
        except ValueError:
            return base_value
    return str(raw)


def _load_config(path, base_mpx, base_rds):
    config = configparser.ConfigParser(interpolation=None)
    config.read(path)
    if "MPX" in config:
        section = config["MPX"]
        for key in list(base_mpx.keys()):
            if key in section:
                base_mpx[key] = _coerce_value(section.get(key), base_mpx[key])
    if "RDS" in config:
        section = config["RDS"]
        for key in list(base_rds.keys()):
            if key in section:
                base_rds[key] = _coerce_value(section.get(key), base_rds[key])


def _apply_case_settings(toggles, rds_on, processing_rate_hz):
    mpx_state["source_mode"] = "input"
    mpx_state["device_in_idx"] = 0
    mpx_state["mono_mode"] = False
    mpx_state["en_rds"] = True
    mpx_state["pilot_level"] = 0.09
    mpx_state["sum_level"] = 0.9
    mpx_state["diff_level"] = 0.9
    mpx_state["input_gain_db"] = 0.0
    # Keep matrix expectations independent from runtime output trim in config.
    mpx_state["output_gain_db"] = 0.0
    mpx_state["mpx_deviation_khz"] = MAX_DEVIATION_KHZ
    rds_state["rds_level"] = 2.0
    mpx_state["processing_rate_hz"] = int(processing_rate_hz)
    for key, value in toggles.items():
        mpx_state[key] = bool(value)


class ToneGenerator:
    def __init__(self, sample_rate, freq_hz, left_gain, right_gain, amplitude):
        self.sample_rate = sample_rate
        self.freq_hz = freq_hz
        self.left_gain = left_gain
        self.right_gain = right_gain
        self.amplitude = amplitude
        self.phase = 0.0

    def block(self, frames, dtype):
        t = (np.arange(frames, dtype=dtype) / self.sample_rate) + self.phase
        tone = (self.amplitude * np.sin(2 * np.pi * self.freq_hz * t)).astype(dtype, copy=False)
        self.phase = (self.phase + frames / self.sample_rate) % 1.0
        left = tone * self.left_gain
        right = tone * self.right_gain
        return np.column_stack((left, right))


def _render_mpx(sample_rate, seconds, warmup_seconds, tone_mode):
    total_frames = max(1, int(round(sample_rate * seconds)))
    warmup_frames = max(0, int(round(sample_rate * warmup_seconds)))
    engine = FMEngine(sample_rate)
    tone_freq = float(mpx_state.get("test_tone_freq", 1000.0))
    sum_level = float(mpx_state.get("sum_level", 0.9))
    diff_level = float(mpx_state.get("diff_level", 0.9))
    pre_b = engine.pre_b
    pre_a = engine.pre_a
    if pre_b.size > 1 or pre_a.size > 1:
        w = 2 * np.pi * tone_freq / engine.proc_rate
        _, h = dsp_signal.freqz(pre_b, pre_a, worN=[w])
        pre_gain = float(np.abs(h[0]))
    else:
        pre_gain = 1.0
    if tone_mode == "stereo":
        tone_target = STEREO_MAX
        denom = diff_level * max(pre_gain, 1e-6)
        tone_amp = tone_target / denom if denom > 0 else 0.0
        tone = ToneGenerator(sample_rate, tone_freq, 1.0, -1.0, min(tone_amp, 1.0))
    else:
        tone_target = BASEBAND_MAX
        denom = sum_level * max(pre_gain, 1e-6)
        tone_amp = tone_target / denom if denom > 0 else 0.0
        tone = ToneGenerator(sample_rate, tone_freq, 1.0, 1.0, min(tone_amp, 1.0))

    if warmup_frames:
        remaining = warmup_frames
        warm = np.zeros((min(BLOCKSIZE, warmup_frames), 2), dtype=engine.dtype)
        while remaining > 0:
            frames = min(BLOCKSIZE, remaining)
            block = tone.block(frames, engine.dtype)
            if warm.shape[0] != frames:
                warm = np.zeros((frames, 2), dtype=engine.dtype)
            engine._process_frame(warm, frames, block)
            remaining -= frames

    output = np.zeros((total_frames, 2), dtype=engine.dtype)
    idx = 0
    while idx < total_frames:
        frames = min(BLOCKSIZE, total_frames - idx)
        block = output[idx : idx + frames]
        in_block = tone.block(frames, engine.dtype)
        engine._process_frame(block, frames, in_block)
        idx += frames
    return output[:, 0].astype(np.float32, copy=False)


def _rds_baseband_rms(data, sample_rate, rds_freq, lp_hz=5000.0):
    if data.size == 0:
        return 0.0
    t = np.arange(data.size, dtype=np.float64) / float(sample_rate)
    sin = np.sin(2 * np.pi * rds_freq * t)
    cos = np.cos(2 * np.pi * rds_freq * t)
    i_sig = data * sin
    q_sig = data * cos
    sos = dsp_signal.butter(4, lp_hz, btype="low", fs=sample_rate, output="sos")
    i_sig = dsp_signal.sosfilt(sos, i_sig)
    q_sig = dsp_signal.sosfilt(sos, q_sig)
    trim = int(sample_rate * 0.05)
    if i_sig.size > trim:
        i_sig = i_sig[trim:]
        q_sig = q_sig[trim:]
    return float(np.sqrt(np.mean(i_sig**2 + q_sig**2)))


def _guard_band_report(data, sample_rate, composite_rms):
    bands = [
        ("audio_guard_15-18.5k", 15000.0, 18500.0),
        ("pilot_guard_20-23k", 20000.0, 23000.0),
        ("stereo_guard_53-54k", 53000.0, 54000.0),
        ("hf_guard_60-90k", 60000.0, min(sample_rate / 2.0, 90000.0)),
    ]
    report = []
    for name, lo, hi in bands:
        if hi <= lo + 1.0:
            continue
        rms, peak = _bandpass_stats(data, sample_rate, lo, hi)
        dbc = _dbfs(rms / composite_rms) if composite_rms > 0 else -120.0
        report.append((name, lo, hi, rms, peak, dbc))
    return report


def _print_guard_report(guard_report):
    warn = False
    for name, lo, hi, rms, peak, dbc in guard_report:
        if dbc > -35.0:
            warn = True
        print(
            "{}: {:.0f}-{:.0f} Hz RMS {:.6f} ({:.2f} dBc), peak {:.6f}".format(
                name, lo, hi, rms, dbc, peak
            )
        )
    print("Guard band check: {}".format("WARN" if warn else "OK"))


def _write_single_wav(path, sample_rate, data):
    from scipy.io import wavfile

    pcm = np.clip(data, -1.0, 1.0)
    wavfile.write(path, sample_rate, (pcm * 32767.0).astype(np.int16))


def _run_inspect(
    sample_rate,
    duration,
    warmup,
    processing_rate_hz,
    base_mpx,
    base_rds,
    wav_path,
    plot_path,
):
    _reset_state(base_mpx, base_rds)
    toggles = {key: bool(base_mpx.get(key, False)) for key in TOGGLES}
    _apply_case_settings(toggles, True, processing_rate_hz)
    data = _render_mpx(sample_rate, duration, warmup, "stereo")
    wav_path.parent.mkdir(parents=True, exist_ok=True)
    _write_single_wav(wav_path, sample_rate, data)
    print(f"Wrote WAV: {wav_path}")

    metrics = analyze_array(sample_rate, data, nperseg=32768)
    print("Composite RMS: {:.6f} ({:.2f} dBFS)".format(metrics["rms"], _dbfs(metrics["rms"])))
    print(
        "Pilot 19 kHz RMS: {:.6f} ({:.2f} dBFS)".format(
            metrics["pilot_rms"], _dbfs(metrics["pilot_rms"])
        )
    )
    print(
        "Stereo band RMS (23-53 kHz): {:.6f} ({:.2f} dBFS)".format(
            metrics["stereo_rms"], _dbfs(metrics["stereo_rms"])
        )
    )
    print(
        "RDS band RMS (54-60 kHz): {:.6f} ({:.2f} dBFS)".format(
            metrics["rds_rms"], _dbfs(metrics["rds_rms"])
        )
    )
    guard_report = _guard_band_report(data, sample_rate, metrics["rms"])
    _print_guard_report(guard_report)

    if plot_path:
        return _plot_spectrum(metrics, plot_path)
    return 0


def _check_metrics(metrics, tone_mode):
    errors = []
    if not np.isfinite(metrics["peak"]) or not np.isfinite(metrics["rms"]):
        errors.append("non-finite composite metrics")
    if metrics["rms"] <= 1e-6:
        errors.append("silent output")
    if metrics["peak"] > COMPOSITE_MAX:
        errors.append("composite exceeds 75 kHz deviation")
    if metrics["pilot_rms"] < PILOT_RMS_MIN or metrics["pilot_rms"] > PILOT_RMS_MAX:
        errors.append("pilot out of 8-10% spec")
    if metrics["rds_peak"] * MAX_DEVIATION_KHZ < RDS_DEV_MIN_KHZ:
        errors.append("rds deviation below 1.0 kHz")
    if metrics["rds_peak"] * MAX_DEVIATION_KHZ > RDS_DEV_MAX_KHZ:
        errors.append("rds deviation above 7.5 kHz")
    if tone_mode == "mono":
        if metrics["baseband_peak"] > BASEBAND_MAX + BASEBAND_TOL:
            errors.append("baseband exceeds 90% spec")
    else:
        if metrics["stereo_peak"] > STEREO_MAX + STEREO_TOL:
            errors.append("stereo subcarrier exceeds 90% spec")
    rds_freq = float(rds_state.get("rds_freq", RDS_FREQ))
    if abs(rds_freq - RDS_FREQ_HZ) > RDS_FREQ_TOL_HZ:
        errors.append("rds subcarrier frequency out of spec")
    return errors


def _case_id(toggles, rds_on, processing_rate_hz):
    parts = [f"{key}={int(val)}" for key, val in toggles.items()]
    parts.append(f"rds={int(rds_on)}")
    parts.append(f"pr={int(processing_rate_hz)}")
    return "mpx_" + "_".join(parts)


def main():
    parser = argparse.ArgumentParser(description="Offline MPX/RDS matrix test")
    parser.add_argument("--duration", type=float, default=2.0)
    parser.add_argument("--warmup", type=float, default=0.1)
    parser.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)
    parser.add_argument("--config", type=str, default=None)
    parser.add_argument("--processing-rates", type=str, default="0")
    parser.add_argument("--report", type=str, default="captures/matrix_report.jsonl")
    parser.add_argument("--keep-wavs", action="store_true")
    parser.add_argument("--outdir", type=str, default="captures/matrix_wavs")
    parser.add_argument("--single-wav", type=str, default=None)
    parser.add_argument(
        "--plot", type=str, default=None, help="Write PNG spectrum plot for --single-wav"
    )
    parser.add_argument("--inspect", action="store_true", help="Run suite + single WAV inspection")
    parser.add_argument("--inspect-wav", type=str, default=None, help="WAV path for --inspect")
    parser.add_argument(
        "--inspect-plot", type=str, default=None, help="PNG spectrum path for --inspect"
    )
    args = parser.parse_args()

    sample_rate = int(args.sample_rate)
    if sample_rate < 48000:
        print("Sample rate too low for MPX testing", file=sys.stderr)
        return 2

    outdir = Path(args.outdir)
    report_path = Path(args.report)
    if args.keep_wavs:
        outdir.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)

    base_mpx = mpx_state.copy()
    base_rds = rds_default_state.copy()
    if args.config:
        _load_config(args.config, base_mpx, base_rds)

    processing_rates = []
    for part in args.processing_rates.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            processing_rates.append(int(part))
        except ValueError:
            pass
    if not processing_rates:
        processing_rates = [0]

    if args.inspect:
        inspect_wav = (
            Path(args.inspect_wav) if args.inspect_wav else Path("captures/inspect/inspect_mpx.wav")
        )
        inspect_plot = (
            Path(args.inspect_plot)
            if args.inspect_plot
            else Path("captures/inspect/inspect_spectrum.png")
        )

    if args.single_wav:
        out_path = Path(args.single_wav)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        _reset_state(base_mpx, base_rds)
        _apply_case_settings({key: False for key in TOGGLES}, True, processing_rates[0])
        data = _render_mpx(sample_rate, args.duration, args.warmup, "stereo")
        _write_single_wav(out_path, sample_rate, data)
        print(f"Wrote WAV: {out_path}")
        if args.plot:
            report = analyze_array(sample_rate, data, nperseg=32768)
            return _plot_spectrum(report, args.plot)
        return 0

    report_file = report_path.open("w", encoding="utf-8")
    failures = []
    total_cases = 0

    for processing_rate_hz in processing_rates:
        for combo in itertools.product([False, True], repeat=len(TOGGLES)):
            toggles = {key: bool(val) for key, val in zip(TOGGLES, combo)}
            rds_on = True
            _reset_state(base_mpx, base_rds)
            _apply_case_settings(toggles, rds_on, processing_rate_hz)
            for tone_mode in ("mono", "stereo"):
                data = _render_mpx(sample_rate, args.duration, args.warmup, tone_mode)
                metrics = analyze_array(sample_rate, data, nperseg=32768)
                rds_freq = float(rds_state.get("rds_freq", RDS_FREQ))
                rds_bb_rms = _rds_baseband_rms(data, sample_rate, rds_freq)
                errors = _check_metrics(metrics, tone_mode)

                case = {
                    "case": _case_id(toggles, rds_on, processing_rate_hz),
                    "tone_mode": tone_mode,
                    "processing_rate_hz": processing_rate_hz,
                    "rds_enabled": rds_on,
                    "toggles": toggles,
                    "metrics": {
                        "peak": metrics["peak"],
                        "rms": metrics["rms"],
                        "baseband_rms": metrics["baseband_rms"],
                        "baseband_peak": metrics["baseband_peak"],
                        "pilot_rms": metrics["pilot_rms"],
                        "rds_rms": metrics["rds_rms"],
                        "rds_bb_rms": rds_bb_rms,
                        "rds_peak": metrics["rds_peak"],
                        "stereo_rms": metrics["stereo_rms"],
                        "stereo_peak": metrics["stereo_peak"],
                        "hf_rms": metrics["hf_rms"],
                    },
                    "errors": errors,
                }
                report_file.write(json.dumps(case, sort_keys=True) + "\n")
                report_file.flush()

                total_cases += 1
                if errors:
                    failures.append((case["case"] + f"_{tone_mode}", ", ".join(errors)))

                if args.keep_wavs:
                    wav_path = outdir / f"{case['case']}_{tone_mode}.wav"
                    from scipy.io import wavfile

                    pcm = np.clip(data, -1.0, 1.0)
                    wavfile.write(wav_path, sample_rate, (pcm * 32767.0).astype(np.int16))

    report_file.close()

    if args.inspect:
        print("\nRunning inspection pass...")
        inspect_code = _run_inspect(
            sample_rate,
            args.duration,
            args.warmup,
            processing_rates[0],
            base_mpx,
            base_rds,
            inspect_wav,
            inspect_plot,
        )
        if inspect_code:
            return inspect_code

    failures = sorted(set(failures))

    print(f"Cases: {total_cases}")
    print(f"Report: {report_path}")
    if failures:
        print(f"Failures: {len(failures)}")
        for case_id, msg in failures[:25]:
            print(f"- {case_id}: {msg}")
        if len(failures) > 25:
            print(f"... {len(failures) - 25} more failures")
        return 1

    print("All cases passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
