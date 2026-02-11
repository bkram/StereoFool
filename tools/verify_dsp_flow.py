#!/usr/bin/env python3
import argparse
import configparser
import json
import math
import os
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.append(os.path.dirname(os.path.dirname(__file__)))

import numpy as np

from analyze_mpx import _bandpass_stats, analyze_array
from stereofool.audio import FMEngine
from stereofool.constants import BLOCKSIZE, DEFAULT_SAMPLE_RATE
from stereofool.state import mpx_state, rds_default_state, rds_state


EPS = 1e-9


@dataclass
class StageResult:
    stage: str
    passed: bool
    metric: str
    value: float
    threshold: str
    detail: str


def _db_ratio(a: float, b: float) -> float:
    return 20.0 * math.log10(max(a, EPS) / max(b, EPS))


def _rms(x: np.ndarray) -> float:
    if x.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(x * x)))


def _segment_rms(x: np.ndarray, sample_rate: int, start_s: float, end_s: float) -> float:
    i0 = max(0, int(round(start_s * sample_rate)))
    i1 = min(x.shape[0], int(round(end_s * sample_rate)))
    if i1 <= i0:
        return 0.0
    return _rms(x[i0:i1])


def _reset_state(base_mpx: dict[str, Any], base_rds: dict[str, Any]) -> None:
    mpx_state.clear()
    mpx_state.update(base_mpx)
    rds_state.clear()
    rds_state.update(base_rds)


def _coerce_value(raw: Any, base_value: Any) -> Any:
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


def _load_config(path: Path, base_mpx: dict[str, Any], base_rds: dict[str, Any]) -> None:
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


def _neutral_mpx(base_mpx: dict[str, Any]) -> dict[str, Any]:
    cfg = base_mpx.copy()
    cfg.update(
        {
            "source_mode": "input",
            "device_in_idx": 0,
            "mono_mode": True,
            "processing_bypass": False,
            "processing_rate_hz": 0,
            "sum_level": 0.9,
            "diff_level": 0.9,
            "input_gain_db": 0.0,
            "agc_enabled": False,
            "hpf_hz": 30.0,
            "hf_trim_db": 0.0,
            "hf_trim_hz": 4000.0,
            "orbass_enabled": False,
            "multiband_enabled": False,
            "stereo_widen_enabled": False,
            "preemphasis_us": 0,
            "preemphasis_hf_control_enabled": False,
            "limit_mpx": False,
            "limit_threshold": 0.98,
            "limit_lookahead_enabled": True,
            "mpx_lpf_enabled": True,
            "mpx_dc_block_enabled": True,
            "mpx_notch_enabled": False,
            "output_gain_db": 0.0,
            "mpx_deviation_khz": 75.0,
            "en_rds": False,
            "output_enabled": True,
        }
    )
    return cfg


def _tone_stereo(
    sample_rate: int,
    seconds: float,
    freq_hz: float,
    amp: float = 0.2,
    left_gain: float = 1.0,
    right_gain: float = 1.0,
) -> np.ndarray:
    frames = max(1, int(round(seconds * sample_rate)))
    t = np.arange(frames, dtype=np.float32) / float(sample_rate)
    tone = (amp * np.sin(2.0 * np.pi * float(freq_hz) * t)).astype(np.float32, copy=False)
    left = (tone * float(left_gain)).astype(np.float32, copy=False)
    right = (tone * float(right_gain)).astype(np.float32, copy=False)
    return np.column_stack((left, right))


def _amplitude_step_tone(sample_rate: int, seconds: float, freq_hz: float) -> np.ndarray:
    frames = max(1, int(round(seconds * sample_rate)))
    t = np.arange(frames, dtype=np.float32) / float(sample_rate)
    amp = np.full(frames, 0.05, dtype=np.float32)
    amp[frames // 2 :] = 0.55
    tone = (amp * np.sin(2.0 * np.pi * float(freq_hz) * t)).astype(np.float32, copy=False)
    return np.column_stack((tone, tone))


def _burst_tone(sample_rate: int, seconds: float, freq_hz: float) -> np.ndarray:
    frames = max(1, int(round(seconds * sample_rate)))
    t = np.arange(frames, dtype=np.float32) / float(sample_rate)
    block = max(16, int(round(0.08 * sample_rate)))
    idx = np.arange(frames) // block
    amp = np.where((idx % 2) == 0, 0.08, 0.72).astype(np.float32, copy=False)
    tone = (amp * np.sin(2.0 * np.pi * float(freq_hz) * t)).astype(np.float32, copy=False)
    return np.column_stack((tone, tone))


def _dc_plus_tone(sample_rate: int, seconds: float, freq_hz: float) -> np.ndarray:
    frames = max(1, int(round(seconds * sample_rate)))
    t = np.arange(frames, dtype=np.float32) / float(sample_rate)
    tone = 0.03 * np.sin(2.0 * np.pi * float(freq_hz) * t)
    sig = (0.20 + tone).astype(np.float32, copy=False)
    return np.column_stack((sig, sig))


def _render_case(
    signal: np.ndarray,
    sample_rate: int,
    base_mpx: dict[str, Any],
    base_rds: dict[str, Any],
    mpx_overrides: dict[str, Any] | None = None,
    rds_overrides: dict[str, Any] | None = None,
    warmup_seconds: float = 0.15,
) -> dict[str, Any]:
    _reset_state(base_mpx, base_rds)
    if mpx_overrides:
        mpx_state.update(mpx_overrides)
    if rds_overrides:
        rds_state.update(rds_overrides)

    signal = np.asarray(signal, dtype=np.float32)
    if signal.ndim != 2 or signal.shape[1] != 2:
        raise ValueError("signal must be Nx2 float32")
    total_frames = int(signal.shape[0])

    pre_blocks: list[np.ndarray] = []

    def _capture(buf: np.ndarray) -> None:
        pre_blocks.append(np.asarray(buf, dtype=np.float32).copy())

    engine = FMEngine(sample_rate=sample_rate, capture_callback=_capture, blocksize=BLOCKSIZE)
    out = np.zeros(total_frames, dtype=np.float32)
    try:
        warmup_frames = max(0, int(round(warmup_seconds * sample_rate)))
        idx = 0
        while idx < warmup_frames:
            frames = min(BLOCKSIZE, warmup_frames - idx)
            out_block = np.zeros((frames, 2), dtype=np.float32)
            in_block = np.zeros((frames, 2), dtype=np.float32)
            engine._process_frame(out_block, frames, in_block)
            idx += frames

        idx = 0
        while idx < total_frames:
            frames = min(BLOCKSIZE, total_frames - idx)
            out_block = np.zeros((frames, 2), dtype=np.float32)
            in_block = signal[idx : idx + frames]
            engine._process_frame(out_block, frames, in_block)
            out[idx : idx + frames] = out_block[:, 0]
            idx += frames
    finally:
        engine.close()

    pre = np.concatenate(pre_blocks).astype(np.float32, copy=False) if pre_blocks else out.copy()
    pre = pre[:total_frames]
    report = analyze_array(sample_rate, out, nperseg=min(32768, max(1024, total_frames)))
    return {"out": out, "pre": pre, "report": report}


def _run_verification(
    sample_rate: int,
    seconds: float,
    base_mpx: dict[str, Any],
    base_rds: dict[str, Any],
) -> tuple[list[StageResult], dict[str, Any]]:
    results: list[StageResult] = []
    raw: dict[str, Any] = {}

    neutral = _neutral_mpx(base_mpx)
    neutral_rds = base_rds.copy()
    neutral_rds["rds_level"] = 2.0

    # 1) Input gain.
    sig = _tone_stereo(sample_rate, seconds, 1000.0, amp=0.16)
    a = _render_case(sig, sample_rate, neutral, neutral_rds, {"input_gain_db": 0.0})
    b = _render_case(sig, sample_rate, neutral, neutral_rds, {"input_gain_db": 6.0})
    input_gain_db = _db_ratio(_rms(b["out"]), _rms(a["out"]))
    results.append(
        StageResult(
            stage="Input Gain",
            passed=input_gain_db > 4.5,
            metric="delta_db",
            value=input_gain_db,
            threshold="> 4.5 dB",
            detail=f"0 dB -> +6 dB produced {input_gain_db:.2f} dB output change",
        )
    )
    raw["input_gain"] = {"off_rms": _rms(a["out"]), "on_rms": _rms(b["out"]), "delta_db": input_gain_db}

    # 2) AGC.
    sig = _amplitude_step_tone(sample_rate, seconds, 1000.0)
    off = _render_case(sig, sample_rate, neutral, neutral_rds, {"agc_enabled": False})
    on = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {
            "agc_enabled": True,
            "agc_target_db": -18.0,
            "agc_max_boost_db": 18.0,
            "agc_max_cut_db": 18.0,
            "agc_attack_ms": 40.0,
            "agc_release_ms": 250.0,
            "agc_noise_floor_db": -55.0,
        },
    )
    half = seconds * 0.5
    off_dyn = _db_ratio(
        _segment_rms(off["out"], sample_rate, half + 0.05, seconds - 0.05),
        _segment_rms(off["out"], sample_rate, 0.05, half - 0.05),
    )
    on_dyn = _db_ratio(
        _segment_rms(on["out"], sample_rate, half + 0.05, seconds - 0.05),
        _segment_rms(on["out"], sample_rate, 0.05, half - 0.05),
    )
    agc_reduction = off_dyn - on_dyn
    results.append(
        StageResult(
            stage="Wideband AGC",
            passed=agc_reduction > 3.0,
            metric="dynamic_range_reduction_db",
            value=agc_reduction,
            threshold="> 3.0 dB",
            detail=f"step dynamic range off={off_dyn:.2f} dB on={on_dyn:.2f} dB",
        )
    )
    raw["agc"] = {"off_dynamic_db": off_dyn, "on_dynamic_db": on_dyn}

    # 3) HPF.
    sig = _tone_stereo(sample_rate, seconds, 40.0, amp=0.28)
    low = _render_case(sig, sample_rate, neutral, neutral_rds, {"hpf_hz": 20.0})
    high = _render_case(sig, sample_rate, neutral, neutral_rds, {"hpf_hz": 250.0})
    hpf_att = _db_ratio(_rms(low["out"]), _rms(high["out"]))
    results.append(
        StageResult(
            stage="Audio HPF",
            passed=hpf_att > 6.0,
            metric="attenuation_db_40hz",
            value=hpf_att,
            threshold="> 6.0 dB",
            detail=f"40 Hz attenuation when hpf_hz 20 -> 250: {hpf_att:.2f} dB",
        )
    )
    raw["hpf"] = {"attenuation_db_40hz": hpf_att}

    # 4) Audio LPF (always active).
    sig_lo = _tone_stereo(sample_rate, seconds, 1000.0, amp=0.20)
    sig_hi = _tone_stereo(sample_rate, seconds, 16000.0, amp=0.20)
    lo = _render_case(sig_lo, sample_rate, neutral, neutral_rds)
    hi = _render_case(sig_hi, sample_rate, neutral, neutral_rds)
    lpf_rel = _db_ratio(_rms(hi["out"]), _rms(lo["out"]))
    results.append(
        StageResult(
            stage="Audio LPF",
            passed=lpf_rel < -6.0,
            metric="rms_16k_vs_1k_db",
            value=lpf_rel,
            threshold="< -6.0 dB",
            detail=f"16 kHz tone relative to 1 kHz: {lpf_rel:.2f} dB",
        )
    )
    raw["lpf"] = {"rms_16k_vs_1k_db": lpf_rel}

    # 5) HF trim.
    sig = _tone_stereo(sample_rate, seconds, 8000.0, amp=0.16)
    off = _render_case(sig, sample_rate, neutral, neutral_rds, {"hf_trim_db": 0.0, "hf_trim_hz": 4000.0})
    on = _render_case(sig, sample_rate, neutral, neutral_rds, {"hf_trim_db": 6.0, "hf_trim_hz": 4000.0})
    hf_trim_delta = _db_ratio(_rms(on["out"]), _rms(off["out"]))
    results.append(
        StageResult(
            stage="HF Trim",
            passed=hf_trim_delta > 2.0,
            metric="delta_db_8khz",
            value=hf_trim_delta,
            threshold="> 2.0 dB",
            detail=f"hf_trim_db 0 -> +6 changed 8 kHz level by {hf_trim_delta:.2f} dB",
        )
    )
    raw["hf_trim"] = {"delta_db_8khz": hf_trim_delta}

    # 6) Audio pilot notch (always active).
    sig18 = _tone_stereo(sample_rate, seconds, 18000.0, amp=0.18)
    sig19 = _tone_stereo(sample_rate, seconds, 19000.0, amp=0.18)
    out18 = _render_case(sig18, sample_rate, neutral, neutral_rds)
    out19 = _render_case(sig19, sample_rate, neutral, neutral_rds)
    notch_rel = _db_ratio(_rms(out19["out"]), _rms(out18["out"]))
    results.append(
        StageResult(
            stage="Pilot Notch",
            passed=notch_rel < -6.0,
            metric="rms_19k_vs_18k_db",
            value=notch_rel,
            threshold="< -6.0 dB",
            detail=f"19 kHz attenuation relative to 18 kHz: {notch_rel:.2f} dB",
        )
    )
    raw["pilot_notch"] = {"rms_19k_vs_18k_db": notch_rel}

    # 7) Orbass.
    frames = max(1, int(round(seconds * sample_rate)))
    t = np.arange(frames, dtype=np.float32) / float(sample_rate)
    sig_m = (
        0.10 * np.sin(2.0 * np.pi * 65.0 * t)
        + 0.08 * np.sin(2.0 * np.pi * 130.0 * t)
        + 0.07 * np.sin(2.0 * np.pi * 1000.0 * t)
    ).astype(np.float32, copy=False)
    sig = np.column_stack((sig_m, sig_m))
    off = _render_case(sig, sample_rate, neutral, neutral_rds, {"orbass_enabled": False})
    on = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {
            "orbass_enabled": True,
            "orbass_amount": 0.85,
            "orbass_freq_hz": 70.0,
            "orbass_harmonics": 0.78,
            "orbass_drive": 1.45,
            "orbass_density": 0.82,
            "orbass_subharmonics_enabled": True,
            "orbass_subharmonics_amount": 0.45,
        },
    )
    off_low, _ = _bandpass_stats(off["out"], sample_rate, 40.0, 180.0)
    off_mid, _ = _bandpass_stats(off["out"], sample_rate, 500.0, 2000.0)
    on_low, _ = _bandpass_stats(on["out"], sample_rate, 40.0, 180.0)
    on_mid, _ = _bandpass_stats(on["out"], sample_rate, 500.0, 2000.0)
    off_ratio = _db_ratio(off_low, off_mid)
    on_ratio = _db_ratio(on_low, on_mid)
    orbass_delta = on_ratio - off_ratio
    results.append(
        StageResult(
            stage="Orbass",
            passed=orbass_delta > 0.5,
            metric="low_to_mid_ratio_delta_db",
            value=orbass_delta,
            threshold="> 0.5 dB",
            detail=f"low/mid ratio off={off_ratio:.2f} dB on={on_ratio:.2f} dB",
        )
    )
    raw["orbass"] = {"off_low_mid_db": off_ratio, "on_low_mid_db": on_ratio}

    # 8) Multiband.
    sig = _burst_tone(sample_rate, seconds, 1000.0)
    off = _render_case(sig, sample_rate, neutral, neutral_rds, {"multiband_enabled": False})
    on = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {
            "multiband_enabled": True,
            "multiband_mode": 3,
            "multiband_low_threshold_db": -30.0,
            "multiband_mid_threshold_db": -30.0,
            "multiband_high_threshold_db": -30.0,
            "multiband_low_ratio": 4.0,
            "multiband_mid_ratio": 4.0,
            "multiband_high_ratio": 4.0,
            "multiband_makeup_db": 0.0,
        },
    )
    off_crest = _db_ratio(off["report"]["peak"], off["report"]["rms"])
    on_crest = _db_ratio(on["report"]["peak"], on["report"]["rms"])
    delta_signal_db = _db_ratio(_rms(on["out"] - off["out"]), _rms(off["out"]))
    results.append(
        StageResult(
            stage="Multiband",
            passed=delta_signal_db > -20.0,
            metric="delta_signal_db",
            value=delta_signal_db,
            threshold="> -20 dB",
            detail=(
                f"off/on waveform delta={delta_signal_db:.2f} dB, "
                f"crest off={off_crest:.2f} dB on={on_crest:.2f} dB"
            ),
        )
    )
    raw["multiband"] = {
        "off_crest_db": off_crest,
        "on_crest_db": on_crest,
        "delta_signal_db": delta_signal_db,
    }

    # 9) Stereo widener.
    sig_l = _tone_stereo(sample_rate, seconds, 1000.0, amp=0.12, left_gain=1.0, right_gain=1.0)
    sig_s = _tone_stereo(sample_rate, seconds, 250.0, amp=0.08, left_gain=1.0, right_gain=-1.0)
    sig = sig_l + sig_s
    off = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {"mono_mode": False, "stereo_widen_enabled": False, "diff_level": 0.9},
    )
    on = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {
            "mono_mode": False,
            "stereo_widen_enabled": True,
            "stereo_widen_width": 1.0,
            "stereo_widen_center": 0.35,
            "stereo_widen_mix": 1.0,
            "diff_level": 0.9,
        },
    )
    off_st, _ = _bandpass_stats(off["out"], sample_rate, 23000.0, 53000.0)
    on_st, _ = _bandpass_stats(on["out"], sample_rate, 23000.0, 53000.0)
    widen_delta = _db_ratio(on_st, off_st)
    results.append(
        StageResult(
            stage="Stereo Widener",
            passed=abs(widen_delta) > 0.8,
            metric="stereo_band_delta_db",
            value=widen_delta,
            threshold="|delta| > 0.8 dB",
            detail=f"23-53 kHz band change from widener: {widen_delta:.2f} dB",
        )
    )
    raw["widener"] = {"delta_db": widen_delta}

    # 10) Pre-emphasis.
    sig = _tone_stereo(sample_rate, seconds, 10000.0, amp=0.12)
    off = _render_case(sig, sample_rate, neutral, neutral_rds, {"preemphasis_us": 0})
    on = _render_case(sig, sample_rate, neutral, neutral_rds, {"preemphasis_us": 75})
    preemph_delta = _db_ratio(_rms(on["out"]), _rms(off["out"]))
    results.append(
        StageResult(
            stage="Pre-emphasis",
            passed=preemph_delta > 4.0,
            metric="delta_db_10khz",
            value=preemph_delta,
            threshold="> 4.0 dB",
            detail=f"preemphasis 0 us -> 75 us changed 10 kHz level by {preemph_delta:.2f} dB",
        )
    )
    raw["preemphasis"] = {"delta_db_10khz": preemph_delta}

    # 11) Pre-emphasis HF control.
    sig = _tone_stereo(sample_rate, seconds, 12000.0, amp=0.38)
    off = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {"preemphasis_us": 75, "preemphasis_hf_control_enabled": False},
    )
    on = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {
            "preemphasis_us": 75,
            "preemphasis_hf_control_enabled": True,
            "preemphasis_hf_control_threshold": 0.14,
            "preemphasis_hf_control_max_reduction_db": 12.0,
            "preemphasis_hf_control_attack_ms": 2.0,
            "preemphasis_hf_control_release_ms": 90.0,
        },
    )
    hf_ctrl_delta = _db_ratio(off["report"]["peak"], on["report"]["peak"])
    results.append(
        StageResult(
            stage="Pre-emphasis HF Control",
            passed=hf_ctrl_delta > 0.5,
            metric="peak_reduction_db",
            value=hf_ctrl_delta,
            threshold="> 0.5 dB",
            detail=f"HF control peak reduction: {hf_ctrl_delta:.2f} dB",
        )
    )
    raw["preemphasis_hf_control"] = {
        "off_peak": off["report"]["peak"],
        "on_peak": on["report"]["peak"],
        "peak_reduction_db": hf_ctrl_delta,
    }

    # 12) Stereo encoder (L-R DSB at 38 kHz).
    side_sig = _tone_stereo(sample_rate, seconds, 1000.0, amp=0.18, left_gain=1.0, right_gain=-1.0)
    mono_sig = _tone_stereo(sample_rate, seconds, 1000.0, amp=0.18, left_gain=1.0, right_gain=1.0)
    side = _render_case(side_sig, sample_rate, neutral, neutral_rds, {"mono_mode": False})
    mono = _render_case(mono_sig, sample_rate, neutral, neutral_rds, {"mono_mode": False})
    side_st, _ = _bandpass_stats(side["out"], sample_rate, 23000.0, 53000.0)
    mono_st, _ = _bandpass_stats(mono["out"], sample_rate, 23000.0, 53000.0)
    stereo_sep = _db_ratio(side_st, mono_st)
    results.append(
        StageResult(
            stage="Stereo Encoder",
            passed=stereo_sep > 12.0,
            metric="side_vs_mono_stereo_band_db",
            value=stereo_sep,
            threshold="> 12.0 dB",
            detail=f"23-53 kHz band side vs mono: {stereo_sep:.2f} dB",
        )
    )
    raw["stereo_encoder"] = {"side_vs_mono_db": stereo_sep}

    # 13) Audio MPX LPF toggle.
    sig = _tone_stereo(sample_rate, seconds, 16000.0, amp=0.14, left_gain=1.0, right_gain=-1.0)
    off = _render_case(
        sig, sample_rate, neutral, neutral_rds, {"mono_mode": False, "mpx_lpf_enabled": False}
    )
    on = _render_case(
        sig, sample_rate, neutral, neutral_rds, {"mono_mode": False, "mpx_lpf_enabled": True}
    )
    off_hf, _ = _bandpass_stats(off["out"], sample_rate, 54000.0, 70000.0)
    on_hf, _ = _bandpass_stats(on["out"], sample_rate, 54000.0, 70000.0)
    mpx_lpf_att = _db_ratio(off_hf, on_hf)
    results.append(
        StageResult(
            stage="Audio-MPX LPF",
            passed=mpx_lpf_att > 2.0,
            metric="attenuation_db_54to70k",
            value=mpx_lpf_att,
            threshold="> 2.0 dB",
            detail=f"54-70 kHz attenuation with LPF on: {mpx_lpf_att:.2f} dB",
        )
    )
    raw["audio_mpx_lpf"] = {"attenuation_db": mpx_lpf_att}

    # 14) MPX DC block stage unit check.
    # In full-chain mode, upstream audio HPF already removes DC strongly. Verify this stage directly.
    sig_dc = _dc_plus_tone(sample_rate, seconds, 200.0)[:, 0]
    _reset_state(neutral, neutral_rds)
    mpx_state["mpx_dc_block_enabled"] = False
    eng_off = FMEngine(sample_rate=sample_rate, blocksize=BLOCKSIZE)
    try:
        off_dc = eng_off._apply_mpx_dc_block(sig_dc.copy())
    finally:
        eng_off.close()
    _reset_state(neutral, neutral_rds)
    mpx_state["mpx_dc_block_enabled"] = True
    eng_on = FMEngine(sample_rate=sample_rate, blocksize=BLOCKSIZE)
    try:
        on_dc = eng_on._apply_mpx_dc_block(sig_dc.copy())
    finally:
        eng_on.close()
    mean_off = float(abs(np.mean(off_dc)))
    mean_on = float(abs(np.mean(on_dc)))
    dc_reduction = _db_ratio(mean_off, mean_on)
    results.append(
        StageResult(
            stage="MPX DC Block",
            passed=dc_reduction > 10.0,
            metric="dc_reduction_db",
            value=dc_reduction,
            threshold="> 10.0 dB",
            detail=f"unit-path abs(mean) off={mean_off:.6f}, on={mean_on:.6f}",
        )
    )
    raw["dc_block"] = {"off_abs_mean": mean_off, "on_abs_mean": mean_on, "reduction_db": dc_reduction}

    # 15) MPX notch toggle.
    sig = _tone_stereo(sample_rate, seconds, 19000.0, amp=0.14)
    off = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {"mono_mode": True, "mpx_notch_enabled": False, "mpx_notch_freq_hz": 19000.0, "mpx_notch_q": 12.0},
    )
    on = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {"mono_mode": True, "mpx_notch_enabled": True, "mpx_notch_freq_hz": 19000.0, "mpx_notch_q": 12.0},
    )
    off_19, _ = _bandpass_stats(off["out"], sample_rate, 18500.0, 19500.0)
    on_19, _ = _bandpass_stats(on["out"], sample_rate, 18500.0, 19500.0)
    notch_att = _db_ratio(off_19, on_19)
    results.append(
        StageResult(
            stage="MPX Notch",
            passed=notch_att > 6.0,
            metric="attenuation_db_19khz",
            value=notch_att,
            threshold="> 6.0 dB",
            detail=f"19 kHz notch attenuation: {notch_att:.2f} dB",
        )
    )
    raw["mpx_notch"] = {"attenuation_db_19khz": notch_att}

    # 16) MPX limiter.
    sig = _burst_tone(sample_rate, seconds, 1000.0)
    off = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {"mono_mode": False, "limit_mpx": False, "preemphasis_us": 50, "input_gain_db": 8.0},
    )
    on = _render_case(
        sig,
        sample_rate,
        neutral,
        neutral_rds,
        {
            "mono_mode": False,
            "limit_mpx": True,
            "limit_threshold": 0.65,
            "limit_lookahead_enabled": True,
            "limit_lookahead_ms": 5.0,
            "preemphasis_us": 50,
            "input_gain_db": 8.0,
        },
    )
    limiter_reduction = _db_ratio(off["report"]["peak"], on["report"]["peak"])
    results.append(
        StageResult(
            stage="MPX Limiter",
            passed=limiter_reduction > 1.5,
            metric="peak_reduction_db",
            value=limiter_reduction,
            threshold="> 1.5 dB",
            detail=f"peak off={off['report']['peak']:.4f}, on={on['report']['peak']:.4f}",
        )
    )
    raw["mpx_limiter"] = {
        "off_peak": off["report"]["peak"],
        "on_peak": on["report"]["peak"],
        "peak_reduction_db": limiter_reduction,
    }

    # 17) Deviation scaling.
    sig = _tone_stereo(sample_rate, seconds, 1000.0, amp=0.14)
    a = _render_case(sig, sample_rate, neutral, neutral_rds, {"mpx_deviation_khz": 75.0})
    b = _render_case(sig, sample_rate, neutral, neutral_rds, {"mpx_deviation_khz": 50.0})
    measured = _db_ratio(_rms(b["out"]), _rms(a["out"]))
    expected = 20.0 * math.log10(50.0 / 75.0)
    error = abs(measured - expected)
    results.append(
        StageResult(
            stage="Deviation Scale",
            passed=error < 0.8,
            metric="abs_error_db",
            value=error,
            threshold="< 0.8 dB",
            detail=f"measured={measured:.2f} dB expected={expected:.2f} dB",
        )
    )
    raw["deviation_scale"] = {"measured_db": measured, "expected_db": expected, "error_db": error}

    # 18) Pilot injection.
    sig = _tone_stereo(sample_rate, seconds, 1000.0, amp=0.12)
    off = _render_case(sig, sample_rate, neutral, neutral_rds, {"mono_mode": True, "pilot_level": 0.09})
    on = _render_case(sig, sample_rate, neutral, neutral_rds, {"mono_mode": False, "pilot_level": 0.09})
    off_p, _ = _bandpass_stats(off["out"], sample_rate, 18500.0, 19500.0)
    on_p, _ = _bandpass_stats(on["out"], sample_rate, 18500.0, 19500.0)
    pilot_delta = _db_ratio(on_p, off_p)
    results.append(
        StageResult(
            stage="Pilot Injection",
            passed=pilot_delta > 12.0 and 0.055 <= on_p <= 0.095,
            metric="pilot_band_delta_db",
            value=pilot_delta,
            threshold="> 12 dB and RMS 0.055..0.095",
            detail=f"pilot RMS off={off_p:.5f}, on={on_p:.5f} ({on_p*100.0:.2f}% FS)",
        )
    )
    raw["pilot"] = {"off_rms": off_p, "on_rms": on_p, "delta_db": pilot_delta}

    # 19) RDS injection.
    sig = _tone_stereo(sample_rate, seconds, 1000.0, amp=0.12)
    off = _render_case(sig, sample_rate, neutral, neutral_rds, {"mono_mode": False, "en_rds": False})
    on = _render_case(sig, sample_rate, neutral, neutral_rds, {"mono_mode": False, "en_rds": True}, {"rds_level": 2.0})
    off_r, _ = _bandpass_stats(off["out"], sample_rate, 54000.0, 60000.0)
    on_r, _ = _bandpass_stats(on["out"], sample_rate, 54000.0, 60000.0)
    rds_delta = _db_ratio(on_r, off_r)
    results.append(
        StageResult(
            stage="RDS Injection",
            passed=rds_delta > 8.0 and on_r > 0.01,
            metric="rds_band_delta_db",
            value=rds_delta,
            threshold="> 8 dB and on_rms > 0.01",
            detail=f"RDS RMS off={off_r:.5f}, on={on_r:.5f}",
        )
    )
    raw["rds"] = {"off_rms": off_r, "on_rms": on_r, "delta_db": rds_delta}

    # 20) Output gain (post-MPX only).
    sig = _tone_stereo(sample_rate, seconds, 1000.0, amp=0.08)
    off = _render_case(sig, sample_rate, neutral, neutral_rds, {"output_gain_db": 0.0})
    on = _render_case(sig, sample_rate, neutral, neutral_rds, {"output_gain_db": 6.0})
    pre_delta = _db_ratio(_rms(on["pre"]), _rms(off["pre"]))
    post_delta = _db_ratio(_rms(on["out"]), _rms(off["out"]))
    output_gain_ok = abs(pre_delta) < 0.4 and post_delta > 4.0
    results.append(
        StageResult(
            stage="Output Gain",
            passed=output_gain_ok,
            metric="post_minus_pre_delta_db",
            value=post_delta - pre_delta,
            threshold="pre ~0 dB, post > 4 dB",
            detail=f"pre delta={pre_delta:.2f} dB, post delta={post_delta:.2f} dB",
        )
    )
    raw["output_gain"] = {"pre_delta_db": pre_delta, "post_delta_db": post_delta}

    return results, raw


def _print_results(results: list[StageResult]) -> None:
    width = max(len(r.stage) for r in results) if results else 12
    print("DSP Workflow Verification")
    print("=" * 96)
    print(f"{'Stage'.ljust(width)}  {'Status':6s}  {'Metric':28s}  {'Value':>10s}  {'Threshold'}")
    print("-" * 96)
    for item in results:
        status = "PASS" if item.passed else "FAIL"
        print(
            f"{item.stage.ljust(width)}  {status:6s}  {item.metric:28s}  "
            f"{item.value:10.3f}  {item.threshold}"
        )
        print(f"{'':{width}}          {item.detail}")
    print("-" * 96)
    passes = sum(1 for r in results if r.passed)
    total = len(results)
    print(f"Summary: {passes}/{total} stages passed")


def main() -> int:
    parser = argparse.ArgumentParser(description="Stage-by-stage offline DSP flow verification")
    parser.add_argument("--config", type=str, default=None, help="Optional config baseline (stereofool.ini)")
    parser.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)
    parser.add_argument("--duration", type=float, default=1.2)
    parser.add_argument("--json", type=str, default=None, help="Write JSON report to file")
    args = parser.parse_args()

    sample_rate = int(args.sample_rate)
    if sample_rate < 96000:
        print("Sample rate too low; use >= 96 kHz for full MPX workflow verification.", file=sys.stderr)
        return 2

    base_mpx = mpx_state.copy()
    base_rds = rds_default_state.copy()
    if args.config:
        cfg_path = Path(args.config)
        if not cfg_path.exists():
            print(f"Config not found: {cfg_path}", file=sys.stderr)
            return 2
        _load_config(cfg_path, base_mpx, base_rds)

    results, raw = _run_verification(sample_rate, float(args.duration), base_mpx, base_rds)
    _print_results(results)

    if args.json:
        out_path = Path(args.json)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "sample_rate": sample_rate,
            "duration_s": float(args.duration),
            "results": [asdict(r) for r in results],
            "raw": raw,
        }
        out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(f"Wrote JSON report: {out_path}")

    failed = [r for r in results if not r.passed]
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
