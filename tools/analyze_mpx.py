#!/usr/bin/env python3
import argparse
import math
import sys
from pathlib import Path

import numpy as np
from scipy import signal as dsp_signal
from scipy.io import wavfile


def _to_float(signal, dtype):
    if np.issubdtype(dtype, np.integer):
        max_val = np.iinfo(dtype).max
        return signal.astype(np.float32) / max_val
    return signal.astype(np.float32)


def _dbfs(value, floor_db=-120.0):
    if value <= 0:
        return floor_db
    return 20.0 * math.log10(value)


def _band_rms(freqs, psd, f_lo, f_hi):
    band = (freqs >= f_lo) & (freqs <= f_hi)
    if not np.any(band):
        return 0.0
    df = freqs[1] - freqs[0]
    power = float(np.sum(psd[band]) * df)
    return math.sqrt(power)


def _bandpass_stats(data, sample_rate, f_lo, f_hi, order=6):
    nyq = sample_rate / 2.0
    lo = max(1.0, min(f_lo, nyq - 1.0))
    hi = max(lo + 1.0, min(f_hi, nyq - 1.0))
    sos = dsp_signal.butter(order, [lo, hi], btype="bandpass", fs=sample_rate, output="sos")
    filtered = dsp_signal.sosfilt(sos, data)
    # Drop a short transient at the start.
    trim = int(sample_rate * 0.05)
    if filtered.size > trim:
        filtered = filtered[trim:]
    if not filtered.size:
        return 0.0, 0.0
    rms = float(np.sqrt(np.mean(filtered**2)))
    peak = float(np.max(np.abs(filtered)))
    return rms, peak


def analyze_array(sample_rate, data, nperseg):
    if data.ndim > 1:
        data = data[:, 0]
    data = _to_float(data, data.dtype)
    if data.size == 0:
        raise ValueError("Empty audio buffer")

    duration = data.size / float(sample_rate)
    peak = float(np.max(np.abs(data)))
    rms = float(np.sqrt(np.mean(data**2)))

    nperseg = min(nperseg, data.size)
    if nperseg < 1024:
        nperseg = min(1024, data.size)
    freqs, psd = dsp_signal.welch(
        data,
        fs=sample_rate,
        window="hann",
        nperseg=nperseg,
        noverlap=nperseg // 2,
        detrend=False,
        scaling="density",
    )

    baseband_rms, baseband_peak = _bandpass_stats(data, sample_rate, 30.0, 15000.0)
    pilot_rms, pilot_peak = _bandpass_stats(data, sample_rate, 18500.0, 19500.0)
    rds_rms, rds_peak = _bandpass_stats(data, sample_rate, 54000.0, 60000.0)
    stereo_rms, stereo_peak = _bandpass_stats(data, sample_rate, 23000.0, 53000.0)
    hf_rms, _ = _bandpass_stats(data, sample_rate, 60000.0, min(sample_rate / 2.0, 90000.0))

    report = {
        "sample_rate": sample_rate,
        "duration_s": duration,
        "peak": peak,
        "rms": rms,
        "crest_db": _dbfs(peak / rms) if rms > 0 else -120.0,
        "baseband_rms": baseband_rms,
        "baseband_peak": baseband_peak,
        "pilot_rms": pilot_rms,
        "pilot_peak": pilot_peak,
        "rds_rms": rds_rms,
        "rds_peak": rds_peak,
        "stereo_rms": stereo_rms,
        "stereo_peak": stereo_peak,
        "hf_rms": hf_rms,
        "freqs": freqs,
        "psd": psd,
    }
    return report


def analyze(path, nperseg):
    sample_rate, data = wavfile.read(path)
    return analyze_array(sample_rate, data, nperseg)


def _smooth_curve(values, window):
    if window <= 1:
        return values
    kernel = np.ones(window, dtype=np.float32) / float(window)
    return np.convolve(values, kernel, mode="same")


def _plot_spectrum(report, out_path):
    try:
        import matplotlib.pyplot as plt
        from matplotlib.ticker import FuncFormatter
    except ImportError:
        print("matplotlib is required for --plot output", file=sys.stderr)
        return 2
    freqs = report["freqs"]
    psd = report["psd"]
    power = np.maximum(psd, 1e-20)
    psd_db = 10.0 * np.log10(power)
    min_hz = 20.0
    max_hz = freqs[-1]
    log_freqs = np.logspace(np.log10(min_hz), np.log10(max_hz), 1200)
    psd_log = np.interp(log_freqs, freqs, psd_db)
    plt.figure(figsize=(10.5, 5.5))
    plt.semilogx(log_freqs, psd_log, color="#1f77b4", linewidth=1.0)
    plt.title("MPX Spectrum (Welch PSD, 0–Nyquist)")

    def _fmt_hz(value, _pos):
        if value >= 1000:
            return f"{value / 1000:.1f}k"
        return f"{int(value)}"

    ax = plt.gca()
    ticks = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 96000]
    ticks = [t for t in ticks if min_hz <= t <= max_hz]
    ax.set_xticks(ticks)
    ax.xaxis.set_major_formatter(FuncFormatter(_fmt_hz))
    plt.xlabel("Frequency (Hz, 0–Nyquist)")
    plt.ylabel("PSD (dBFS/Hz)")
    plt.grid(True, which="both", alpha=0.3)
    plt.axvline(19000.0, color="#ff7f0e", alpha=0.35, linewidth=1.0)
    plt.axvspan(23000.0, 53000.0, color="#2ca02c", alpha=0.08)
    plt.axvspan(54000.0, 60000.0, color="#d62728", alpha=0.08)
    plt.xlim(min_hz, max_hz)
    plt.tight_layout()
    plt.savefig(out_path, dpi=150)
    plt.close()
    print(f"Wrote spectrum plot: {out_path}")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Analyze MPX WAV capture")
    parser.add_argument("wav_path", type=str)
    parser.add_argument("--nperseg", type=int, default=32768)
    parser.add_argument("--plot", type=str, default=None, help="Write PNG spectrum plot (dBFS/Hz)")
    args = parser.parse_args()

    wav_path = Path(args.wav_path)
    if not wav_path.exists():
        print(f"File not found: {wav_path}", file=sys.stderr)
        return 1

    report = analyze(wav_path, args.nperseg)
    sample_rate = report["sample_rate"]
    duration = report["duration_s"]

    print(f"File: {wav_path}")
    print(f"Sample rate: {sample_rate} Hz")
    print(f"Duration: {duration:.2f} s")
    print(f"Composite peak: {report['peak']:.6f} ({_dbfs(report['peak']):.2f} dBFS)")
    print(f"Composite RMS: {report['rms']:.6f} ({_dbfs(report['rms']):.2f} dBFS)")
    print(
        "Composite deviation (peak/RMS): {:.2f} kHz / {:.2f} kHz".format(
            report["peak"] * 75.0,
            report["rms"] * 75.0,
        )
    )
    print(f"Crest factor: {report['crest_db']:.2f} dB")
    print(
        "Pilot 19 kHz RMS: {:.6f} ({:.2f} dBFS, {:.2f} dBc)".format(
            report["pilot_rms"],
            _dbfs(report["pilot_rms"]),
            _dbfs(report["pilot_rms"] / report["rms"]),
        )
    )
    print(
        "Pilot 19 kHz RMS deviation: {:.2f} kHz ({:.2f}% of 75 kHz)".format(
            report["pilot_rms"] * 75.0,
            report["pilot_rms"] * 100.0,
        )
    )
    print(
        "Pilot 19 kHz peak: {:.6f} ({:.2f} dBFS, {:.2f} kHz)".format(
            report["pilot_peak"],
            _dbfs(report["pilot_peak"]),
            report["pilot_peak"] * 75.0,
        )
    )
    print(
        "RDS band RMS (54-60 kHz): {:.6f} ({:.2f} dBFS, {:.2f} dBc)".format(
            report["rds_rms"],
            _dbfs(report["rds_rms"]),
            _dbfs(report["rds_rms"] / report["rms"]),
        )
    )
    print("RDS band RMS deviation: {:.2f} kHz".format(report["rds_rms"] * 75.0))
    print(
        "RDS band peak (54-60 kHz): {:.6f} ({:.2f} dBFS, {:.2f} kHz)".format(
            report["rds_peak"],
            _dbfs(report["rds_peak"]),
            report["rds_peak"] * 75.0,
        )
    )
    print(
        "Stereo band RMS (23-53 kHz): {:.6f} ({:.2f} dBFS, {:.2f} dBc)".format(
            report["stereo_rms"],
            _dbfs(report["stereo_rms"]),
            _dbfs(report["stereo_rms"] / report["rms"]),
        )
    )
    print(
        "HF band RMS (60-90 kHz): {:.6f} ({:.2f} dBFS, {:.2f} dBc)".format(
            report["hf_rms"],
            _dbfs(report["hf_rms"]),
            _dbfs(report["hf_rms"] / report["rms"]),
        )
    )
    if report["hf_rms"] > 0:
        hf_vs_rds = report["hf_rms"] / report["rds_rms"] if report["rds_rms"] > 0 else 0.0
        print("HF/RDS ratio: {:.2f} dB".format(_dbfs(hf_vs_rds)))
    print("Est. peak deviation (assumes 1.0 = 75 kHz): {:.2f} kHz".format(report["peak"] * 75.0))
    if args.plot:
        return _plot_spectrum(report, args.plot)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
