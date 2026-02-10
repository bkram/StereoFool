import math
import queue
import threading
import logging
import time
from collections import Counter
from typing import Any, cast

import numpy as np
import sounddevice as sd
from scipy import signal as dsp_signal

from stereofool.constants import BLOCKSIZE, PILOT_FREQ, PREBUFFER_SECONDS
from stereofool.rds import RDSSubcarrier
from stereofool.state import dsp_control, meter_lock, meter_state, mpx_state, wave_lock, wave_state

logger = logging.getLogger("stereofool")


class AudioInputReader:
    def __init__(self, device_idx, sample_rate, dtype, blocksize=BLOCKSIZE):
        self.device_idx = device_idx
        self.sample_rate = sample_rate
        self.dtype = np.dtype(dtype)
        self.bytes_per_sample = self.dtype.itemsize
        self.buffer = bytearray()
        self.lock = threading.Lock()
        self.stream = None
        self.running = False
        self._last_status_log = 0.0
        self._last_status_summary_log = 0.0
        self._status_counts: Counter[str] = Counter()
        self.blocksize = max(1, int(blocksize))
        self.target_buffer_frames = max(self.blocksize * 6, int(self.sample_rate * 0.12))
        self.max_buffer_frames = max(self.target_buffer_frames * 4, self.blocksize * 12)
        self.max_buffer_bytes = self.max_buffer_frames * 2 * self.bytes_per_sample
        self.trimmed_frames = 0
        self.underfilled_frames = 0
        self.drift_correction_events = 0
        self.last_frame = np.zeros(2, dtype=self.dtype)

    def start(self):
        if self.device_idx is None or self.device_idx < 0:
            return
        self.running = True
        self.stream = sd.InputStream(
            device=self.device_idx,
            samplerate=self.sample_rate,
            blocksize=self.blocksize,
            channels=2,
            latency="high",
            callback=self._callback,
        )
        self.stream.start()

    def stop(self):
        self.running = False
        if self.stream:
            try:
                self.stream.stop()
                self.stream.close()
            except Exception:
                pass
            self.stream = None
        if self._status_counts:
            logger.warning(
                "StereoFool: input reader status totals: %s",
                ", ".join(f"{k}={v}" for k, v in sorted(self._status_counts.items())),
            )
        if self.trimmed_frames:
            logger.warning("StereoFool: input reader trimmed %s backlog frames", self.trimmed_frames)
        if self.underfilled_frames:
            logger.warning("StereoFool: input reader underfilled %s frames", self.underfilled_frames)
        if self.drift_correction_events:
            logger.info(
                "StereoFool: input reader applied %s drift-correction resamples",
                self.drift_correction_events,
            )

    def _callback(self, indata, frames, _time_info, _status):
        if not self.running:
            return
        if _status:
            self._accumulate_status(_status)
            now = time.monotonic()
            if now - self._last_status_log >= 1.0:
                logger.warning("StereoFool: input reader status: %s", _status)
                self._last_status_log = now
            if now - self._last_status_summary_log >= 5.0 and self._status_counts:
                logger.warning(
                    "StereoFool: input reader status totals: %s",
                    ", ".join(f"{k}={v}" for k, v in sorted(self._status_counts.items())),
                )
                self._last_status_summary_log = now
        with self.lock:
            self.buffer.extend(indata.astype(self.dtype, copy=False).tobytes())
            if len(self.buffer) > self.max_buffer_bytes:
                frame_bytes = 2 * self.bytes_per_sample
                trim_frames = (len(self.buffer) - self.max_buffer_bytes) // frame_bytes
                if trim_frames > 0:
                    trim_bytes = trim_frames * frame_bytes
                    del self.buffer[:trim_bytes]
                    self.trimmed_frames += trim_frames

    def buffered_frames(self):
        with self.lock:
            return len(self.buffer) // (2 * self.bytes_per_sample)

    def _read_frames_raw(self, frames):
        needed = frames * 2 * self.bytes_per_sample
        with self.lock:
            frame_bytes = 2 * self.bytes_per_sample
            buffered_frames = len(self.buffer) // frame_bytes
            if buffered_frames > self.max_buffer_frames:
                drop_frames = buffered_frames - self.target_buffer_frames
                if drop_frames > 0:
                    drop_bytes = drop_frames * frame_bytes
                    del self.buffer[:drop_bytes]
                    self.trimmed_frames += drop_frames
                    self._status_counts["backlog_trim"] += 1
            if len(self.buffer) >= needed:
                chunk = bytes(self.buffer[:needed])
                del self.buffer[:needed]
            else:
                chunk = bytes(self.buffer)
                self.buffer.clear()
        if len(chunk) < needed:
            missing_frames = (needed - len(chunk)) // (2 * self.bytes_per_sample)
            self.underfilled_frames += max(0, missing_frames)
            if missing_frames > 0:
                self._status_counts["reader_underfill"] += 1
                filler = np.tile(self.last_frame, (missing_frames, 1)).astype(self.dtype, copy=False)
                chunk += filler.tobytes()
        data = np.frombuffer(chunk, dtype=self.dtype).reshape(frames, 2).copy()
        if data.shape[0] > 0:
            self.last_frame = data[-1].copy()
        return data

    def read_frames(self, frames):
        return self._read_frames_raw(frames)

    def read_frames_clock_adaptive(self, frames):
        frame_count = max(1, int(frames))
        level = self.buffered_frames()
        error = float(level - self.target_buffer_frames)
        max_adjust = max(1, int(frame_count * 0.03))
        adjust = int(round(error * 0.004))
        if adjust > max_adjust:
            adjust = max_adjust
        elif adjust < -max_adjust:
            adjust = -max_adjust
        src_frames = max(1, frame_count + adjust)
        raw = self._read_frames_raw(src_frames)
        if raw.shape[0] == frame_count:
            return raw
        self.drift_correction_events += 1
        if raw.shape[0] <= 1:
            return np.tile(self.last_frame, (frame_count, 1)).astype(self.dtype, copy=False)
        old_x = np.linspace(0.0, 1.0, num=raw.shape[0], endpoint=False, dtype=np.float64)
        new_x = np.linspace(0.0, 1.0, num=frame_count, endpoint=False, dtype=np.float64)
        out = np.empty((frame_count, 2), dtype=self.dtype)
        out[:, 0] = np.interp(new_x, old_x, raw[:, 0]).astype(self.dtype, copy=False)
        out[:, 1] = np.interp(new_x, old_x, raw[:, 1]).astype(self.dtype, copy=False)
        self.last_frame = out[-1].copy()
        return out

    def _accumulate_status(self, status):
        status_map = {
            "input_overflow": "in_overflow",
            "input_underflow": "in_underflow",
            "output_overflow": "out_overflow",
            "output_underflow": "out_underflow",
            "priming_output": "priming_output",
        }
        seen_flag = False
        for attr, key in status_map.items():
            try:
                if bool(getattr(status, attr)):
                    self._status_counts[key] += 1
                    seen_flag = True
            except Exception:
                continue
        if not seen_flag:
            self._status_counts[str(status)] += 1


class FMEngine:
    def __init__(
        self,
        sample_rate,
        capture_callback=None,
        monitor_callback=None,
        monitor_rate=48000,
        blocksize=BLOCKSIZE,
    ):
        self.sample_rate = sample_rate
        self.dtype = np.float32
        self.proc_rate = self._resolve_processing_rate()
        self.phase = 0.0
        self.tone_phase = 0.0
        self.pan_phase = 0.0
        self.audio_in = None
        self.capture_callback = capture_callback
        self.monitor_callback = monitor_callback
        self.monitor_rate = int(monitor_rate)
        self.telemetry_interval_s = 0.05
        self._last_telemetry_enqueue = 0.0
        self.telemetry_queue = queue.Queue(maxsize=2)
        self.telemetry_stop = threading.Event()
        self.telemetry_thread = threading.Thread(target=self._telemetry_loop, daemon=True)
        self.telemetry_thread.start()
        self._time_cache: dict[tuple[int, int], np.ndarray] = {}
        self._zero_cache: dict[int, np.ndarray] = {}
        self._resample_window_cache: dict[tuple[int, int], np.ndarray] = {}
        self._init_lookahead_state()
        self.audio_headroom_gain = 1.0
        self.hf_trim_db = float(mpx_state.get("hf_trim_db", 0.0))
        self.hf_trim_hz = float(mpx_state.get("hf_trim_hz", 4000.0))
        self.hpf_hz = float(mpx_state.get("hpf_hz", 30.0))
        self._init_audio_filters()
        bpf_low = 23000
        bpf_high = min(53000, (self.sample_rate / 2) - 1000)
        if bpf_high <= bpf_low:
            bpf_high = bpf_low + 1000
        self.bpf_sos = dsp_signal.butter(
            8, [bpf_low, bpf_high], btype="bandpass", fs=self.sample_rate, output="sos"
        )
        self.bpf_zi = (dsp_signal.sosfilt_zi(self.bpf_sos) * 0).astype(self.dtype)
        audio_mpx_cutoff = min(53000.0, (self.sample_rate / 2) - 1000.0)
        if audio_mpx_cutoff <= 20000.0:
            audio_mpx_cutoff = max(20000.0, self.sample_rate * 0.4)
        self.audio_mpx_lpf_sos = dsp_signal.butter(
            6, audio_mpx_cutoff, btype="low", fs=self.sample_rate, output="sos"
        )
        self.audio_mpx_lpf_zi = (dsp_signal.sosfilt_zi(self.audio_mpx_lpf_sos) * 0).astype(
            self.dtype
        )
        self._init_mpx_cleanup()
        self._init_preemphasis()
        self._init_dynamics()
        self._init_monitor_filters()
        self.rds = RDSSubcarrier(self.sample_rate)
        self.rds_enabled = bool(mpx_state.get("en_rds"))
        self.logged_input_fallback = False
        self._last_status_log = 0.0
        self._last_status_summary_log = 0.0
        self._status_counts: Counter[str] = Counter()
        self.blocksize = max(1, int(blocksize))

    def _init_lookahead_state(self):
        self.lookahead_audio_pair_buffer = None
        self.lookahead_audio_pair_samples = 0
        self.lookahead_audio_pair_gain = 1.0
        self.lookahead_preemph_pair_buffer = None
        self.lookahead_preemph_pair_samples = 0
        self.lookahead_preemph_pair_gain = 1.0
        self.lookahead_mpx_buffer = None
        self.lookahead_mpx_samples = 0
        self.lookahead_mpx_gain = 1.0
        self.lookahead_composite_buffer = None
        self.lookahead_composite_samples = 0
        self.lookahead_composite_gain = 1.0

    def _log_stream_status(self, status, label):
        if not status:
            return
        self._accumulate_status(label, status)
        now = time.monotonic()
        if now - self._last_status_log >= 1.0:
            logger.warning("StereoFool: %s stream status: %s", label, status)
            self._last_status_log = now
        if now - self._last_status_summary_log >= 5.0 and self._status_counts:
            logger.warning(
                "StereoFool: stream status totals: %s",
                ", ".join(f"{k}={v}" for k, v in sorted(self._status_counts.items())),
            )
            self._last_status_summary_log = now

    def _accumulate_status(self, label, status):
        status_map = {
            "input_overflow": "in_overflow",
            "input_underflow": "in_underflow",
            "output_overflow": "out_overflow",
            "output_underflow": "out_underflow",
            "priming_output": "priming_output",
        }
        seen_flag = False
        for attr, key in status_map.items():
            try:
                if bool(getattr(status, attr)):
                    self._status_counts[f"{label}:{key}"] += 1
                    seen_flag = True
            except Exception:
                continue
        if not seen_flag:
            self._status_counts[f"{label}:{status}"] += 1

    def _get_time_base(self, frames, sample_rate):
        key = (int(frames), int(sample_rate))
        cached = self._time_cache.get(key)
        if cached is None:
            cached = np.arange(frames, dtype=self.dtype) / float(sample_rate)
            self._time_cache[key] = cached
        return cached

    def _get_zeros(self, length):
        n = int(length)
        cached = self._zero_cache.get(n)
        if cached is None:
            cached = np.zeros(n, dtype=self.dtype)
            self._zero_cache[n] = cached
        return cached.copy()

    def _get_resample_window(self, up: int, down: int) -> np.ndarray:
        up_i = max(1, int(up))
        down_i = max(1, int(down))
        g = math.gcd(up_i, down_i)
        up_i //= g
        down_i //= g
        key = (up_i, down_i)
        cached = self._resample_window_cache.get(key)
        if cached is not None:
            return cached
        max_rate = max(up_i, down_i)
        cutoff = 1.0 / float(max_rate)
        half_len = 10 * max_rate
        taps = dsp_signal.firwin(
            2 * half_len + 1,
            cutoff,
            window=cast(Any, ("kaiser", 5.0)),
        )
        cached = (np.asarray(taps, dtype=self.dtype) * float(up_i)).astype(self.dtype, copy=False)
        self._resample_window_cache[key] = cached
        return cached

    def close(self, timeout=0.5):
        self.telemetry_stop.set()
        if self.telemetry_thread.is_alive():
            self.telemetry_thread.join(timeout=timeout)
        if self._status_counts:
            logger.warning(
                "StereoFool: stream status totals: %s",
                ", ".join(f"{k}={v}" for k, v in sorted(self._status_counts.items())),
            )

    def _enqueue_telemetry(self, item):
        try:
            self.telemetry_queue.put_nowait(item)
            return
        except queue.Full:
            pass
        try:
            self.telemetry_queue.get_nowait()
        except queue.Empty:
            pass
        try:
            self.telemetry_queue.put_nowait(item)
        except queue.Full:
            pass

    def _telemetry_loop(self):
        while not self.telemetry_stop.is_set() or not self.telemetry_queue.empty():
            try:
                item = self.telemetry_queue.get(timeout=0.1)
            except queue.Empty:
                continue
            try:
                input_rms = float(item["input_rms"])
                input_peak = float(item["input_peak"])
                input_pre_rms = float(item["input_pre_rms"])
                input_pre_peak = float(item["input_pre_peak"])
                mpx_rms = float(item["mpx_rms"])
                mpx_peak = float(item["mpx_peak"])
                limiter_active = bool(item["limiter_active"])
                preemph_limit_enabled = bool(item["preemph_limit_enabled"])
                preemph_limit_active = bool(item["preemph_limit_active"])
                composite_clip_enabled = bool(item["composite_clip_enabled"])
                composite_clip_active = bool(item["composite_clip_active"])
                scope_left = item["scope_left"]
                scope_right = item["scope_right"]
                mpx_pre_gain = item["mpx_pre_gain"]
                proc_frames = int(item["proc_frames"])

                output_rms = float(np.sqrt(np.mean(mpx_pre_gain**2))) if mpx_pre_gain.size else 0.0
                output_peak = float(np.max(np.abs(mpx_pre_gain))) if mpx_pre_gain.size else 0.0

                if (
                    scope_left is not None
                    and scope_right is not None
                    and scope_left.size
                    and scope_right.size
                ):
                    input_scope = (scope_left + scope_right) * 0.5
                    left_vu = float(np.sqrt(np.mean(scope_left**2)))
                    right_vu = float(np.sqrt(np.mean(scope_right**2)))
                    left_rms = left_vu
                    right_rms = right_vu
                else:
                    input_scope = np.zeros(proc_frames, dtype=self.dtype)
                    left_vu = 0.0
                    right_vu = 0.0
                    left_rms = 0.0
                    right_rms = 0.0

                out_scope = mpx_pre_gain
                scope_points = 128
                in_step = max(1, int(len(input_scope) / scope_points))
                out_step = max(1, int(len(out_scope) / scope_points))
                input_wave = input_scope[::in_step][:scope_points].astype(np.float32)
                mpx_wave = out_scope[::out_step][:scope_points].astype(np.float32)
                with wave_lock:
                    wave_state["input_wave"] = input_wave.tolist()
                    wave_state["mpx_wave"] = mpx_wave.tolist()

                with meter_lock:
                    def _smooth_meter(current: float, target: float, rise: float, fall: float) -> float:
                        alpha = rise if target >= current else fall
                        return (current * (1.0 - alpha)) + (target * alpha)

                    meter_state["input_rms"] = _smooth_meter(
                        float(meter_state["input_rms"]), input_rms, rise=0.35, fall=0.14
                    )
                    meter_state["input_rms_l"] = _smooth_meter(
                        float(meter_state["input_rms_l"]), left_rms, rise=0.35, fall=0.14
                    )
                    meter_state["input_rms_r"] = _smooth_meter(
                        float(meter_state["input_rms_r"]), right_rms, rise=0.35, fall=0.14
                    )
                    meter_state["mpx_rms"] = _smooth_meter(
                        float(meter_state["mpx_rms"]), mpx_rms, rise=0.35, fall=0.14
                    )
                    meter_state["input_peak"] = max(meter_state["input_peak"] * 0.965, input_peak)
                    meter_state["mpx_peak"] = max(meter_state["mpx_peak"] * 0.965, mpx_peak)
                    meter_state["input_vu"] = _smooth_meter(
                        float(meter_state["input_vu"]), input_rms, rise=0.42, fall=0.12
                    )
                    meter_state["input_vu_l"] = _smooth_meter(
                        float(meter_state["input_vu_l"]), left_vu, rise=0.42, fall=0.12
                    )
                    meter_state["input_vu_r"] = _smooth_meter(
                        float(meter_state["input_vu_r"]), right_vu, rise=0.42, fall=0.12
                    )
                    meter_state["mpx_vu"] = _smooth_meter(
                        float(meter_state["mpx_vu"]), mpx_rms, rise=0.42, fall=0.12
                    )
                    meter_state["input_pre_rms"] = _smooth_meter(
                        float(meter_state["input_pre_rms"]), input_pre_rms, rise=0.35, fall=0.14
                    )
                    meter_state["input_pre_peak"] = max(
                        meter_state["input_pre_peak"] * 0.965, input_pre_peak
                    )
                    meter_state["input_pre_vu"] = _smooth_meter(
                        float(meter_state["input_pre_vu"]), input_pre_rms, rise=0.42, fall=0.12
                    )
                    meter_state["output_rms"] = _smooth_meter(
                        float(meter_state["output_rms"]), output_rms, rise=0.35, fall=0.14
                    )
                    meter_state["output_peak"] = max(meter_state["output_peak"] * 0.965, output_peak)
                    meter_state["output_vu"] = _smooth_meter(
                        float(meter_state["output_vu"]), output_rms, rise=0.42, fall=0.12
                    )
                    meter_state["limiter_active"] = limiter_active
                    meter_state["multiband_enabled"] = bool(mpx_state.get("multiband_enabled"))
                    meter_state["multiband_active"] = bool(mpx_state.get("multiband_enabled"))
                    meter_state["preemph_limit_enabled"] = preemph_limit_enabled
                    meter_state["preemph_limit_active"] = preemph_limit_active
                    meter_state["composite_clip_enabled"] = composite_clip_enabled
                    meter_state["composite_clip_active"] = composite_clip_active
            except Exception:
                continue

    def _resolve_processing_rate(self):
        raw = mpx_state.get("processing_rate_hz", 0)
        try:
            setting = int(raw)
        except (TypeError, ValueError):
            setting = 0
        if setting <= 0:
            return self.sample_rate
        if setting > self.sample_rate:
            return self.sample_rate
        if setting < 8000:
            return self.sample_rate
        return setting

    def _init_audio_filters(self):
        self.audio_lpf_sos = dsp_signal.butter(
            10, 15000, btype="low", fs=self.proc_rate, output="sos"
        )
        self.audio_lpf_zi_l = (dsp_signal.sosfilt_zi(self.audio_lpf_sos) * 0).astype(self.dtype)
        self.audio_lpf_zi_r = (dsp_signal.sosfilt_zi(self.audio_lpf_sos) * 0).astype(self.dtype)
        self.audio_notch_b, self.audio_notch_a = dsp_signal.iirnotch(
            PILOT_FREQ, 35.0, fs=self.proc_rate
        )
        self.audio_notch_zi_l = (
            dsp_signal.lfilter_zi(self.audio_notch_b, self.audio_notch_a) * 0
        ).astype(self.dtype)
        self.audio_notch_zi_r = (
            dsp_signal.lfilter_zi(self.audio_notch_b, self.audio_notch_a) * 0
        ).astype(self.dtype)
        self.hf_b, self.hf_a = self._hf_trim_coeffs(
            self.hf_trim_db, self.hf_trim_hz, self.proc_rate
        )
        self.hf_zi_l, self.hf_zi_r = self._hf_trim_state()
        self.hpf_sos = dsp_signal.butter(
            2, self.hpf_hz, btype="high", fs=self.proc_rate, output="sos"
        )
        self.hpf_zi_l = (dsp_signal.sosfilt_zi(self.hpf_sos) * 0).astype(self.dtype)
        self.hpf_zi_r = (dsp_signal.sosfilt_zi(self.hpf_sos) * 0).astype(self.dtype)

    def _init_preemphasis(self):
        self.preemphasis_us = int(mpx_state.get("preemphasis_us", 50))
        self.pre_b, self.pre_a = self._preemphasis_coeffs(self.preemphasis_us, self.proc_rate)
        if len(self.pre_b) > 1 or len(self.pre_a) > 1:
            self.pre_zi_sum = (dsp_signal.lfilter_zi(self.pre_b, self.pre_a) * 0).astype(self.dtype)
            self.pre_zi_diff = (dsp_signal.lfilter_zi(self.pre_b, self.pre_a) * 0).astype(
                self.dtype
            )
        else:
            self.pre_zi_sum = np.zeros(0, dtype=self.dtype)
            self.pre_zi_diff = np.zeros(0, dtype=self.dtype)

    def _init_dynamics(self):
        self.mb_env_low = 0.0
        self.mb_env_mid = 0.0
        self.mb_env_high = 0.0
        self.mb_sc_low = 1e-9
        self.mb_sc_mid = 1e-9
        self.mb_sc_high = 1e-9
        self.mb5_env = [0.0] * 5
        self.mb5_sc = [1e-9] * 5
        self._init_wideband_agc()
        self._init_orbass()
        self._init_preemphasis_hf_control()
        self.widen_side_gain = 1.0
        self.widen_mid_gain = 1.0
        self.widen_mix = 1.0
        self.composite_limit_gain = 1.0
        self.composite_clip_trim_gain = 1.0
        self.composite_safety_gain = 1.0
        self.preemph_drive_gain = 1.0
        self._init_multiband_filters()

    def _init_wideband_agc(self):
        self.agc_gain = 1.0
        self.agc_initialized = False

    def _init_orbass(self):
        self.orbass_freq_hz = 95.0
        self.orbass_amount_target = 0.35
        self.orbass_harmonics_target = 0.35
        self.orbass_amount = self.orbass_amount_target
        self.orbass_harmonics = self.orbass_harmonics_target
        self.orbass_target_ratio = 0.33
        self.orbass_ratio_deadband = 0.04
        self.orbass_ratio_est = self.orbass_target_ratio
        self.orbass_mix = 0.0
        self.orbass_adaptive_target = 0.0
        self.orbass_adaptive_gain = 0.0
        self.orbass_level_est = 1e-3
        self.orbass_hold_seconds = 0.12
        self.orbass_hold_remaining = 0.0
        self.orbass_makeup_gain = 1.0
        self.orbass_lpf_sos = np.array([[1.0, 0.0, 0.0, 1.0, 0.0, 0.0]], dtype=self.dtype)
        self.orbass_hpf_sos = np.array([[1.0, 0.0, 0.0, 1.0, 0.0, 0.0]], dtype=self.dtype)
        self.orbass_harm_lpf_sos = np.array([[1.0, 0.0, 0.0, 1.0, 0.0, 0.0]], dtype=self.dtype)
        self.orbass_lpf_zi = (dsp_signal.sosfilt_zi(self.orbass_lpf_sos) * 0).astype(self.dtype)
        self.orbass_hpf_zi = (dsp_signal.sosfilt_zi(self.orbass_hpf_sos) * 0).astype(self.dtype)
        self.orbass_harm_lpf_zi = (
            dsp_signal.sosfilt_zi(self.orbass_harm_lpf_sos) * 0
        ).astype(self.dtype)
        self._refresh_orbass(force=True)

    def _init_preemphasis_hf_control(self):
        cutoff_hz = min(4500.0, (self.proc_rate / 2.0) - 200.0)
        cutoff_hz = max(1200.0, cutoff_hz)
        self.preemph_hf_sc_sos = dsp_signal.butter(
            2, cutoff_hz, btype="high", fs=self.proc_rate, output="sos"
        )
        self.preemph_hf_sc_zi_sum = (dsp_signal.sosfilt_zi(self.preemph_hf_sc_sos) * 0).astype(
            self.dtype
        )
        self.preemph_hf_sc_zi_diff = (dsp_signal.sosfilt_zi(self.preemph_hf_sc_sos) * 0).astype(
            self.dtype
        )
        self.preemph_hf_gain = 1.0
        self.preemph_hf_level_est = 0.0
        self.preemph_hf_hold_s = 0.0

    def _init_multiband_filters(self):
        raw_mode = mpx_state.get("multiband_mode", 3)
        try:
            self.mb_mode = 5 if int(raw_mode) == 5 else 3
        except (TypeError, ValueError):
            self.mb_mode = 3
        self.mb_low_hz = float(mpx_state.get("multiband_low_hz", 400.0))
        self.mb_high_hz = float(mpx_state.get("multiband_high_hz", 2000.0))
        low = min(self.mb_low_hz, (self.proc_rate / 2) - 100.0)
        high = min(self.mb_high_hz, (self.proc_rate / 2) - 100.0)
        if high <= low + 50.0:
            high = low + 50.0
        self.mb_lp1_sos, self.mb_hp1_sos = self._linkwitz_riley_sos(low)
        self.mb_lp2_sos, self.mb_hp2_sos = self._linkwitz_riley_sos(high)
        self.mb_lp1_zi_l = (dsp_signal.sosfilt_zi(self.mb_lp1_sos) * 0).astype(self.dtype)
        self.mb_lp1_zi_r = (dsp_signal.sosfilt_zi(self.mb_lp1_sos) * 0).astype(self.dtype)
        self.mb_hp1_zi_l = (dsp_signal.sosfilt_zi(self.mb_hp1_sos) * 0).astype(self.dtype)
        self.mb_hp1_zi_r = (dsp_signal.sosfilt_zi(self.mb_hp1_sos) * 0).astype(self.dtype)
        self.mb_lp2_zi_l = (dsp_signal.sosfilt_zi(self.mb_lp2_sos) * 0).astype(self.dtype)
        self.mb_lp2_zi_r = (dsp_signal.sosfilt_zi(self.mb_lp2_sos) * 0).astype(self.dtype)
        self.mb_hp2_zi_l = (dsp_signal.sosfilt_zi(self.mb_hp2_sos) * 0).astype(self.dtype)
        self.mb_hp2_zi_r = (dsp_signal.sosfilt_zi(self.mb_hp2_sos) * 0).astype(self.dtype)
        nyquist_limit = (self.proc_rate / 2.0) - 100.0
        x1 = float(mpx_state.get("multiband_x1_hz", 80.0))
        x2 = float(mpx_state.get("multiband_x2_hz", 320.0))
        x3 = float(mpx_state.get("multiband_x3_hz", 1200.0))
        x4 = float(mpx_state.get("multiband_x4_hz", 5000.0))
        x1 = max(40.0, min(nyquist_limit - 400.0, x1))
        x2 = max(x1 + 40.0, min(nyquist_limit - 300.0, x2))
        x3 = max(x2 + 80.0, min(nyquist_limit - 200.0, x3))
        x4 = max(x3 + 120.0, min(nyquist_limit - 100.0, x4))
        self.mb_x1_hz = x1
        self.mb_x2_hz = x2
        self.mb_x3_hz = x3
        self.mb_x4_hz = x4
        self.mb5_lp1_sos, self.mb5_hp1_sos = self._linkwitz_riley_sos(x1)
        self.mb5_lp2_sos, self.mb5_hp2_sos = self._linkwitz_riley_sos(x2)
        self.mb5_lp3_sos, self.mb5_hp3_sos = self._linkwitz_riley_sos(x3)
        self.mb5_lp4_sos, self.mb5_hp4_sos = self._linkwitz_riley_sos(x4)
        self.mb5_lp1_zi_l = (dsp_signal.sosfilt_zi(self.mb5_lp1_sos) * 0).astype(self.dtype)
        self.mb5_lp1_zi_r = (dsp_signal.sosfilt_zi(self.mb5_lp1_sos) * 0).astype(self.dtype)
        self.mb5_hp1_zi_l = (dsp_signal.sosfilt_zi(self.mb5_hp1_sos) * 0).astype(self.dtype)
        self.mb5_hp1_zi_r = (dsp_signal.sosfilt_zi(self.mb5_hp1_sos) * 0).astype(self.dtype)
        self.mb5_lp2_zi_l = (dsp_signal.sosfilt_zi(self.mb5_lp2_sos) * 0).astype(self.dtype)
        self.mb5_lp2_zi_r = (dsp_signal.sosfilt_zi(self.mb5_lp2_sos) * 0).astype(self.dtype)
        self.mb5_hp2_zi_l = (dsp_signal.sosfilt_zi(self.mb5_hp2_sos) * 0).astype(self.dtype)
        self.mb5_hp2_zi_r = (dsp_signal.sosfilt_zi(self.mb5_hp2_sos) * 0).astype(self.dtype)
        self.mb5_lp3_zi_l = (dsp_signal.sosfilt_zi(self.mb5_lp3_sos) * 0).astype(self.dtype)
        self.mb5_lp3_zi_r = (dsp_signal.sosfilt_zi(self.mb5_lp3_sos) * 0).astype(self.dtype)
        self.mb5_hp3_zi_l = (dsp_signal.sosfilt_zi(self.mb5_hp3_sos) * 0).astype(self.dtype)
        self.mb5_hp3_zi_r = (dsp_signal.sosfilt_zi(self.mb5_hp3_sos) * 0).astype(self.dtype)
        self.mb5_lp4_zi_l = (dsp_signal.sosfilt_zi(self.mb5_lp4_sos) * 0).astype(self.dtype)
        self.mb5_lp4_zi_r = (dsp_signal.sosfilt_zi(self.mb5_lp4_sos) * 0).astype(self.dtype)
        self.mb5_hp4_zi_l = (dsp_signal.sosfilt_zi(self.mb5_hp4_sos) * 0).astype(self.dtype)
        self.mb5_hp4_zi_r = (dsp_signal.sosfilt_zi(self.mb5_hp4_sos) * 0).astype(self.dtype)
        self.mb5_env = [0.0] * 5
        self.mb5_sc = [1e-9] * 5

    def _refresh_multiband_filters(self):
        desired_mode = 3
        try:
            desired_mode = 5 if int(mpx_state.get("multiband_mode", 3)) == 5 else 3
        except (TypeError, ValueError):
            desired_mode = 3
        if desired_mode != getattr(self, "mb_mode", 3):
            self._init_multiband_filters()
            return
        try:
            low = float(mpx_state.get("multiband_low_hz", self.mb_low_hz))
            high = float(mpx_state.get("multiband_high_hz", self.mb_high_hz))
            x1 = float(mpx_state.get("multiband_x1_hz", self.mb_x1_hz))
            x2 = float(mpx_state.get("multiband_x2_hz", self.mb_x2_hz))
            x3 = float(mpx_state.get("multiband_x3_hz", self.mb_x3_hz))
            x4 = float(mpx_state.get("multiband_x4_hz", self.mb_x4_hz))
        except (TypeError, ValueError):
            return
        if (
            abs(low - self.mb_low_hz) > 1.0
            or abs(high - self.mb_high_hz) > 1.0
            or abs(x1 - self.mb_x1_hz) > 1.0
            or abs(x2 - self.mb_x2_hz) > 1.0
            or abs(x3 - self.mb_x3_hz) > 1.0
            or abs(x4 - self.mb_x4_hz) > 1.0
        ):
            self._init_multiband_filters()

    def _linkwitz_riley_sos(self, freq_hz: float) -> tuple[np.ndarray, np.ndarray]:
        lp2_raw = dsp_signal.butter(2, float(freq_hz), btype="low", fs=self.proc_rate, output="sos")
        hp2_raw = dsp_signal.butter(2, float(freq_hz), btype="high", fs=self.proc_rate, output="sos")
        lp2 = np.asarray(lp2_raw, dtype=self.dtype)
        hp2 = np.asarray(hp2_raw, dtype=self.dtype)
        lp4 = np.concatenate((lp2, lp2), axis=0).astype(self.dtype, copy=False)
        hp4 = np.concatenate((hp2, hp2), axis=0).astype(self.dtype, copy=False)
        return lp4, hp4

    def _init_monitor_filters(self):
        self.mon_lpf_sos = dsp_signal.butter(
            6, 15000.0, btype="low", fs=self.sample_rate, output="sos"
        )
        self.mon_lpf_zi = (dsp_signal.sosfilt_zi(self.mon_lpf_sos) * 0).astype(self.dtype)
        self.mon_lpf_zi_diff = (dsp_signal.sosfilt_zi(self.mon_lpf_sos) * 0).astype(self.dtype)
        self.mon_bpf_sos = dsp_signal.butter(
            6, [23000.0, 53000.0], btype="bandpass", fs=self.sample_rate, output="sos"
        )
        self.mon_bpf_zi = (dsp_signal.sosfilt_zi(self.mon_bpf_sos) * 0).astype(self.dtype)
        self._init_monitor_deemphasis()

    def _init_monitor_deemphasis(self):
        self.deemphasis_us = int(mpx_state.get("preemphasis_us", 50))
        if self.deemphasis_us:
            tau = float(self.deemphasis_us) * 1e-6
            de_b, de_a = dsp_signal.bilinear([1.0], [tau, 1.0], fs=self.sample_rate)
            self.de_b = np.asarray(de_b, dtype=self.dtype)
            self.de_a = np.asarray(de_a, dtype=self.dtype)
        else:
            self.de_b = np.array([1.0], dtype=self.dtype)
            self.de_a = np.array([1.0], dtype=self.dtype)
        if self.de_b.shape[0] > 1 or self.de_a.shape[0] > 1:
            self.de_zi_l = (dsp_signal.lfilter_zi(self.de_b, self.de_a) * 0).astype(self.dtype)
            self.de_zi_r = (dsp_signal.lfilter_zi(self.de_b, self.de_a) * 0).astype(self.dtype)
        else:
            self.de_zi_l = np.zeros(0, dtype=self.dtype)
            self.de_zi_r = np.zeros(0, dtype=self.dtype)

    def _refresh_monitor_deemphasis(self):
        current = int(mpx_state.get("preemphasis_us", 0) or 0)
        if current != self.deemphasis_us:
            self.deemphasis_us = current
            self._init_monitor_deemphasis()

    def _monitor_demod(self, mpx, subcarrier):
        if not mpx.size:
            return None
        lpr, self.mon_lpf_zi = dsp_signal.sosfilt(self.mon_lpf_sos, mpx, zi=self.mon_lpf_zi)
        dsb, self.mon_bpf_zi = dsp_signal.sosfilt(self.mon_bpf_sos, mpx, zi=self.mon_bpf_zi)
        diff = 2.0 * dsb * subcarrier
        diff, self.mon_lpf_zi_diff = dsp_signal.sosfilt(
            self.mon_lpf_sos, diff, zi=self.mon_lpf_zi_diff
        )
        diff = -diff
        left = lpr + diff
        right = lpr - diff
        self._refresh_monitor_deemphasis()
        if self.deemphasis_us:
            left, self.de_zi_l = dsp_signal.lfilter(self.de_b, self.de_a, left, zi=self.de_zi_l)
            right, self.de_zi_r = dsp_signal.lfilter(self.de_b, self.de_a, right, zi=self.de_zi_r)
        stereo = np.column_stack((left, right)).astype(np.float32, copy=False)
        if self.monitor_rate != self.sample_rate:
            g = math.gcd(self.sample_rate, self.monitor_rate)
            down = self.sample_rate // g
            up = self.monitor_rate // g
            stereo = self._resample(stereo, up, down, None)
        return stereo

    def _init_mpx_cleanup(self):
        self.mpx_dc_hz = float(mpx_state.get("mpx_dc_block_hz", 2.0))
        dc_hz = max(0.5, min(10.0, self.mpx_dc_hz))
        self.mpx_dc_sos = dsp_signal.butter(
            1, dc_hz, btype="high", fs=self.sample_rate, output="sos"
        )
        self.mpx_dc_zi = (dsp_signal.sosfilt_zi(self.mpx_dc_sos) * 0).astype(self.dtype)
        self.mpx_notch_hz = float(mpx_state.get("mpx_notch_freq_hz", 19000.0))
        self.mpx_notch_q = float(mpx_state.get("mpx_notch_q", 12.0))
        self.mpx_notch_b, self.mpx_notch_a = dsp_signal.iirnotch(
            self.mpx_notch_hz, self.mpx_notch_q, fs=self.sample_rate
        )
        self.mpx_notch_zi = (dsp_signal.lfilter_zi(self.mpx_notch_b, self.mpx_notch_a) * 0).astype(
            self.dtype
        )

    def _refresh_mpx_cleanup(self):
        try:
            dc_hz = float(mpx_state.get("mpx_dc_block_hz", self.mpx_dc_hz))
        except (TypeError, ValueError):
            dc_hz = self.mpx_dc_hz
        dc_hz = max(0.5, min(10.0, dc_hz))
        if abs(dc_hz - self.mpx_dc_hz) > 0.05:
            self.mpx_dc_hz = dc_hz
            self.mpx_dc_sos = dsp_signal.butter(
                1, dc_hz, btype="high", fs=self.sample_rate, output="sos"
            )
            self.mpx_dc_zi = (dsp_signal.sosfilt_zi(self.mpx_dc_sos) * 0).astype(self.dtype)
        try:
            notch_hz = float(mpx_state.get("mpx_notch_freq_hz", self.mpx_notch_hz))
            notch_q = float(mpx_state.get("mpx_notch_q", self.mpx_notch_q))
        except (TypeError, ValueError):
            return
        notch_hz = max(100.0, min(self.sample_rate / 2 - 100.0, notch_hz))
        notch_q = max(0.1, min(50.0, notch_q))
        if abs(notch_hz - self.mpx_notch_hz) > 1.0 or abs(notch_q - self.mpx_notch_q) > 0.1:
            self.mpx_notch_hz = notch_hz
            self.mpx_notch_q = notch_q
            self.mpx_notch_b, self.mpx_notch_a = dsp_signal.iirnotch(
                self.mpx_notch_hz, self.mpx_notch_q, fs=self.sample_rate
            )
            self.mpx_notch_zi = (
                dsp_signal.lfilter_zi(self.mpx_notch_b, self.mpx_notch_a) * 0
            ).astype(self.dtype)

    def _apply_mpx_dc_block(self, mpx):
        if not mpx.size:
            return mpx
        if not bool(mpx_state.get("mpx_dc_block_enabled", True)):
            return mpx
        mpx, self.mpx_dc_zi = dsp_signal.sosfilt(self.mpx_dc_sos, mpx, zi=self.mpx_dc_zi)
        return mpx

    def _apply_mpx_notch(self, mpx):
        if not mpx.size:
            return mpx
        if not bool(mpx_state.get("mpx_notch_enabled", False)):
            return mpx
        mpx, self.mpx_notch_zi = dsp_signal.lfilter(
            self.mpx_notch_b, self.mpx_notch_a, mpx, zi=self.mpx_notch_zi
        )
        return mpx

    def _preemphasis_coeffs(self, tau_us, sample_rate):
        if not tau_us:
            return np.array([1.0], dtype=self.dtype), np.array([1.0], dtype=self.dtype)
        tau = float(tau_us) * 1e-6
        b, a = dsp_signal.bilinear([tau, 1.0], [0.0, 1.0], fs=sample_rate)
        return np.asarray(b, dtype=self.dtype), np.asarray(a, dtype=self.dtype)

    def _smooth_gain(self, current, target, frames, attack_ms, release_ms, sample_rate=None):
        if sample_rate is None:
            sample_rate = self.sample_rate
        tau_ms = float(attack_ms if target < current else release_ms)
        if tau_ms <= 0:
            return target
        tau_samples = max(1, int(tau_ms / 1000.0 * sample_rate))
        coeff = np.exp(-frames / tau_samples)
        return (coeff * current) + ((1 - coeff) * target)

    def _apply_lpf(self, left, right):
        left, self.audio_lpf_zi_l = dsp_signal.sosfilt(
            self.audio_lpf_sos, left, zi=self.audio_lpf_zi_l
        )
        right, self.audio_lpf_zi_r = dsp_signal.sosfilt(
            self.audio_lpf_sos, right, zi=self.audio_lpf_zi_r
        )
        return left, right

    def _apply_pilot_notch(self, left, right):
        left, self.audio_notch_zi_l = dsp_signal.lfilter(
            self.audio_notch_b, self.audio_notch_a, left, zi=self.audio_notch_zi_l
        )
        right, self.audio_notch_zi_r = dsp_signal.lfilter(
            self.audio_notch_b, self.audio_notch_a, right, zi=self.audio_notch_zi_r
        )
        return left, right

    def _hf_trim_coeffs(self, gain_db, cutoff_hz, sample_rate):
        gain_db = float(gain_db)
        if abs(gain_db) < 0.01:
            return np.array([1.0], dtype=self.dtype), np.array([1.0], dtype=self.dtype)
        fs = sample_rate
        cutoff = max(500.0, min(12000.0, float(cutoff_hz)))
        w0 = 2 * np.pi * cutoff / fs
        cos_w0 = np.cos(w0)
        sin_w0 = np.sin(w0)
        slope = 1.0
        A = 10 ** (gain_db / 40.0)
        alpha = sin_w0 / 2 * np.sqrt((A + 1 / A) * (1 / slope - 1) + 2)
        b0 = A * ((A + 1) + (A - 1) * cos_w0 + 2 * np.sqrt(A) * alpha)
        b1 = -2 * A * ((A - 1) + (A + 1) * cos_w0)
        b2 = A * ((A + 1) + (A - 1) * cos_w0 - 2 * np.sqrt(A) * alpha)
        a0 = (A + 1) - (A - 1) * cos_w0 + 2 * np.sqrt(A) * alpha
        a1 = 2 * ((A - 1) - (A + 1) * cos_w0)
        a2 = (A + 1) - (A - 1) * cos_w0 - 2 * np.sqrt(A) * alpha
        b = np.array([b0 / a0, b1 / a0, b2 / a0], dtype=self.dtype)
        a = np.array([1.0, a1 / a0, a2 / a0], dtype=self.dtype)
        return b, a

    def _hf_trim_state(self):
        order = max(len(self.hf_b), len(self.hf_a)) - 1
        if order <= 0:
            return np.zeros(0, dtype=self.dtype), np.zeros(0, dtype=self.dtype)
        zi = np.zeros(order, dtype=self.dtype)
        return zi.copy(), zi.copy()

    def _refresh_hf_trim(self):
        try:
            gain_db = float(mpx_state.get("hf_trim_db", 0.0))
            cutoff_hz = float(mpx_state.get("hf_trim_hz", 4000.0))
        except (TypeError, ValueError):
            return
        cutoff_hz = max(500.0, min(12000.0, cutoff_hz))
        if abs(gain_db - self.hf_trim_db) < 0.05 and abs(cutoff_hz - self.hf_trim_hz) < 1.0:
            return
        self.hf_trim_db = gain_db
        self.hf_trim_hz = cutoff_hz
        self.hf_b, self.hf_a = self._hf_trim_coeffs(
            self.hf_trim_db, self.hf_trim_hz, self.proc_rate
        )
        self.hf_zi_l, self.hf_zi_r = self._hf_trim_state()

    def _apply_hf_trim(self, left, right):
        if len(self.hf_b) < 2 or len(self.hf_a) < 2:
            return left, right
        left, self.hf_zi_l = dsp_signal.lfilter(self.hf_b, self.hf_a, left, zi=self.hf_zi_l)
        right, self.hf_zi_r = dsp_signal.lfilter(self.hf_b, self.hf_a, right, zi=self.hf_zi_r)
        return left, right

    def _apply_hpf(self, left, right):
        left, self.hpf_zi_l = dsp_signal.sosfilt(self.hpf_sos, left, zi=self.hpf_zi_l)
        right, self.hpf_zi_r = dsp_signal.sosfilt(self.hpf_sos, right, zi=self.hpf_zi_r)
        return left, right

    def _apply_wideband_agc(self, left, right):
        if not left.size or not right.size:
            return left, right
        block_time_s = float(left.shape[0]) / max(1.0, float(self.proc_rate))
        enabled = bool(mpx_state.get("agc_enabled", False))
        if not enabled:
            self.agc_initialized = False
            if abs(self.agc_gain - 1.0) < 1e-4:
                return left, right
            alpha = 1.0 - math.exp(-block_time_s / 0.35)
            self.agc_gain += (1.0 - self.agc_gain) * alpha
            return (left * self.agc_gain).astype(self.dtype, copy=False), (
                right * self.agc_gain
            ).astype(self.dtype, copy=False)
        try:
            target_db = float(mpx_state.get("agc_target_db", -18.0))
            max_boost_db = max(0.0, float(mpx_state.get("agc_max_boost_db", 12.0)))
            max_cut_db = max(0.0, float(mpx_state.get("agc_max_cut_db", 0.0)))
            attack_ms = max(5.0, float(mpx_state.get("agc_attack_ms", 250.0)))
            release_ms = max(10.0, float(mpx_state.get("agc_release_ms", 1800.0)))
            noise_floor_db = float(mpx_state.get("agc_noise_floor_db", -50.0))
        except (TypeError, ValueError):
            return left, right
        stereo_rms = float(np.sqrt((np.mean(left * left) + np.mean(right * right)) * 0.5))
        floor_lin = 10 ** (noise_floor_db / 20.0)
        if stereo_rms <= floor_lin:
            target_gain = min(1.0, self.agc_gain)
        else:
            current_db = 20.0 * math.log10(max(stereo_rms, 1e-9))
            gain_db = max(-max_cut_db, min(max_boost_db, target_db - current_db))
            target_gain = 10 ** (gain_db / 20.0)
        if not self.agc_initialized:
            self.agc_gain = target_gain
            self.agc_initialized = True
            return (left * self.agc_gain).astype(self.dtype, copy=False), (
                right * self.agc_gain
            ).astype(self.dtype, copy=False)
        self.agc_gain = self._smooth_gain(
            self.agc_gain,
            target_gain,
            left.shape[0],
            attack_ms=attack_ms,
            release_ms=release_ms,
            sample_rate=self.proc_rate,
        )
        return (left * self.agc_gain).astype(self.dtype, copy=False), (
            right * self.agc_gain
        ).astype(self.dtype, copy=False)

    def _refresh_hpf(self):
        try:
            current = float(mpx_state.get("hpf_hz", self.hpf_hz))
        except (TypeError, ValueError):
            return
        current = max(10.0, min(200.0, current))
        if abs(current - self.hpf_hz) < 0.1:
            return
        self.hpf_hz = current
        self.hpf_sos = dsp_signal.butter(
            2, self.hpf_hz, btype="high", fs=self.proc_rate, output="sos"
        )
        self.hpf_zi_l = (dsp_signal.sosfilt_zi(self.hpf_sos) * 0).astype(self.dtype)
        self.hpf_zi_r = (dsp_signal.sosfilt_zi(self.hpf_sos) * 0).astype(self.dtype)

    def _refresh_orbass(self, force=False):
        try:
            freq_hz = float(mpx_state.get("orbass_freq_hz", self.orbass_freq_hz))
            amount = float(mpx_state.get("orbass_amount", self.orbass_amount_target))
            harmonics = float(mpx_state.get("orbass_harmonics", self.orbass_harmonics_target))
        except (TypeError, ValueError):
            return
        freq_hz = max(45.0, min(220.0, freq_hz))
        amount = max(0.0, min(1.0, amount))
        harmonics = max(0.0, min(1.0, harmonics))
        big_jump = (
            abs(freq_hz - self.orbass_freq_hz) > 8.0
            or abs(amount - self.orbass_amount_target) > 0.12
            or abs(harmonics - self.orbass_harmonics_target) > 0.12
        )
        self.orbass_amount_target = amount
        self.orbass_harmonics_target = harmonics
        if big_jump:
            # Preset/profile jumps: clear adaptive memory so we do not keep stale gain bias.
            self.orbass_adaptive_target = 0.0
            self.orbass_adaptive_gain = 0.0
            self.orbass_ratio_est = self.orbass_target_ratio
            self.orbass_hold_remaining = 0.0
            self.orbass_level_est = 1e-3
            self.orbass_makeup_gain = 1.0
        if not force and abs(freq_hz - self.orbass_freq_hz) < 0.5:
            return
        self.orbass_freq_hz = freq_hz
        nyquist_margin = max(200.0, (self.proc_rate / 2.0) - 200.0)
        lpf_hz = min(self.orbass_freq_hz, nyquist_margin)
        hpf_hz = min(max(120.0, self.orbass_freq_hz * 1.6), nyquist_margin)
        harm_lpf_hz = min(max(280.0, self.orbass_freq_hz * 5.0), nyquist_margin)
        if harm_lpf_hz <= hpf_hz + 20.0:
            harm_lpf_hz = min(hpf_hz + 20.0, nyquist_margin)
        self.orbass_lpf_sos = dsp_signal.butter(
            2, lpf_hz, btype="low", fs=self.proc_rate, output="sos"
        )
        self.orbass_hpf_sos = dsp_signal.butter(
            2, hpf_hz, btype="high", fs=self.proc_rate, output="sos"
        )
        self.orbass_harm_lpf_sos = dsp_signal.butter(
            2, harm_lpf_hz, btype="low", fs=self.proc_rate, output="sos"
        )
        self.orbass_lpf_zi = (dsp_signal.sosfilt_zi(self.orbass_lpf_sos) * 0).astype(self.dtype)
        self.orbass_hpf_zi = (dsp_signal.sosfilt_zi(self.orbass_hpf_sos) * 0).astype(self.dtype)
        self.orbass_harm_lpf_zi = (
            dsp_signal.sosfilt_zi(self.orbass_harm_lpf_sos) * 0
        ).astype(self.dtype)

    def _apply_orbass(self, left, right):
        if not left.size or not right.size:
            return left, right
        enabled = bool(mpx_state.get("orbass_enabled"))
        if not enabled and self.orbass_mix < 1e-4:
            return left, right
        block_time_s = float(left.shape[0]) / max(1.0, float(self.proc_rate))
        alpha = 1.0 - math.exp(-block_time_s / 0.12)
        self.orbass_mix += ((1.0 if enabled else 0.0) - self.orbass_mix) * alpha
        self.orbass_amount += (self.orbass_amount_target - self.orbass_amount) * alpha
        self.orbass_harmonics += (self.orbass_harmonics_target - self.orbass_harmonics) * alpha
        wet_mix = max(0.0, min(1.0, self.orbass_mix))
        amount = max(0.0, min(1.0, self.orbass_amount * wet_mix))
        harmonics = max(0.0, min(1.0, self.orbass_harmonics * wet_mix))
        if amount <= 1e-4 and harmonics <= 1e-4:
            return left, right
        mid = (left + right) * 0.5
        side = (left - right) * 0.5
        low, self.orbass_lpf_zi = dsp_signal.sosfilt(self.orbass_lpf_sos, mid, zi=self.orbass_lpf_zi)
        full_rms = float(np.sqrt(np.mean(mid * mid))) if mid.size else 0.0
        low_rms = float(np.sqrt(np.mean(low * low))) if low.size else 0.0
        low_ratio = low_rms / max(full_rms, 1e-6)

        # Slow ratio tracking keeps Orbass from chasing block-by-block spectral changes.
        ratio_alpha = 1.0 - math.exp(-block_time_s / 0.45)
        self.orbass_ratio_est += (low_ratio - self.orbass_ratio_est) * ratio_alpha
        target_ratio = self.orbass_target_ratio
        deadband = self.orbass_ratio_deadband
        low_enter = max(0.05, target_ratio - deadband)
        high_exit = min(0.9, target_ratio + deadband)
        if self.orbass_ratio_est < low_enter:
            deficit = (low_enter - self.orbass_ratio_est) / low_enter
            self.orbass_adaptive_target = max(0.0, min(1.0, deficit))
        elif self.orbass_ratio_est > high_exit:
            self.orbass_adaptive_target = 0.0

        # Freeze adaptive movement around hard transients to avoid audible crackle/pumping.
        block_peak = float(np.max(np.abs(mid))) if mid.size else 0.0
        level_alpha = 1.0 - math.exp(-block_time_s / 1.1)
        self.orbass_level_est += (full_rms - self.orbass_level_est) * level_alpha
        transient_factor = block_peak / max(1e-6, self.orbass_level_est)
        if transient_factor > 3.5:
            self.orbass_hold_remaining = self.orbass_hold_seconds
        self.orbass_hold_remaining = max(0.0, self.orbass_hold_remaining - block_time_s)
        if self.orbass_hold_remaining <= 0.0:
            # Slow attack/release on adaptive gain: stable long-term behavior.
            adapt_tau = 1.2 if self.orbass_adaptive_target > self.orbass_adaptive_gain else 2.8
            adapt_alpha = 1.0 - math.exp(-block_time_s / adapt_tau)
            self.orbass_adaptive_gain += (
                self.orbass_adaptive_target - self.orbass_adaptive_gain
            ) * adapt_alpha
        adaptive = max(0.0, min(1.0, self.orbass_adaptive_gain))

        # Blend fixed enhancement with adaptive boost; static part keeps tonal consistency.
        boost_gain = 1.0 + (amount * (0.55 + (0.75 * adaptive)))
        low_boost = low * (boost_gain - 1.0)
        drive = 1.0 + (amount * 4.0) + (harmonics * 4.0)
        harmonic_src = np.tanh(low * drive) - np.tanh(low)
        harmonic_band, self.orbass_hpf_zi = dsp_signal.sosfilt(
            self.orbass_hpf_sos, harmonic_src, zi=self.orbass_hpf_zi
        )
        harmonic_band, self.orbass_harm_lpf_zi = dsp_signal.sosfilt(
            self.orbass_harm_lpf_sos, harmonic_band, zi=self.orbass_harm_lpf_zi
        )
        harmonic_gain = harmonics * (0.55 + (0.65 * adaptive))
        enhancement = low_boost + (harmonic_band * harmonic_gain)
        enhancement = 0.85 * np.tanh(enhancement / 0.85)
        mid_out = mid + enhancement
        mid_out *= 1.0 / (1.0 + (0.10 * amount))
        in_mid_rms = float(np.sqrt(np.mean(mid * mid))) if mid.size else 0.0
        out_mid_rms = float(np.sqrt(np.mean(mid_out * mid_out))) if mid_out.size else 0.0
        if out_mid_rms > 1e-7:
            target_makeup = (in_mid_rms / out_mid_rms) ** 0.6
            target_makeup = max(0.90, min(1.18, target_makeup))
            self.orbass_makeup_gain = self._smooth_gain(
                self.orbass_makeup_gain,
                target_makeup,
                left.shape[0],
                attack_ms=35.0,
                release_ms=180.0,
                sample_rate=self.proc_rate,
            )
            mid_out *= self.orbass_makeup_gain
        out_l = mid_out + side
        out_r = mid_out - side
        in_peak = max(
            float(np.max(np.abs(left))) if left.size else 0.0,
            float(np.max(np.abs(right))) if right.size else 0.0,
            1e-6,
        )
        out_peak = max(
            float(np.max(np.abs(out_l))) if out_l.size else 0.0,
            float(np.max(np.abs(out_r))) if out_r.size else 0.0,
            1e-6,
        )
        allowed_peak = in_peak * (1.06 + (0.04 * amount))
        if out_peak > allowed_peak:
            scale = allowed_peak / out_peak
            out_l = left + ((out_l - left) * scale)
            out_r = right + ((out_r - right) * scale)
        return out_l.astype(self.dtype, copy=False), out_r.astype(self.dtype, copy=False)

    def _apply_preemphasis_hf_control(self, baseband, diff):
        if not baseband.size or not diff.size:
            return baseband, diff
        if not self.preemphasis_us or not bool(mpx_state.get("preemphasis_hf_control_enabled", False)):
            if self.preemph_hf_gain < 0.999:
                self.preemph_hf_gain = self._smooth_gain(
                    self.preemph_hf_gain,
                    1.0,
                    baseband.shape[0],
                    attack_ms=100.0,
                    release_ms=300.0,
                    sample_rate=self.proc_rate,
                )
                return (baseband * self.preemph_hf_gain).astype(self.dtype, copy=False), (
                    diff * self.preemph_hf_gain
                ).astype(self.dtype, copy=False)
            return baseband, diff
        try:
            threshold = float(mpx_state.get("preemphasis_hf_control_threshold", 0.32))
            max_reduction_db = float(mpx_state.get("preemphasis_hf_control_max_reduction_db", 8.0))
            attack_ms = float(mpx_state.get("preemphasis_hf_control_attack_ms", 4.0))
            release_ms = float(mpx_state.get("preemphasis_hf_control_release_ms", 120.0))
        except (TypeError, ValueError):
            return baseband, diff
        threshold = max(0.05, min(0.98, threshold))
        max_reduction_db = max(0.0, min(24.0, max_reduction_db))
        attack_ms = max(1.0, min(200.0, attack_ms))
        release_ms = max(10.0, min(2000.0, release_ms))
        block_time_s = float(baseband.shape[0]) / max(1.0, float(self.proc_rate))
        hf_sum, self.preemph_hf_sc_zi_sum = dsp_signal.sosfilt(
            self.preemph_hf_sc_sos, baseband, zi=self.preemph_hf_sc_zi_sum
        )
        hf_diff, self.preemph_hf_sc_zi_diff = dsp_signal.sosfilt(
            self.preemph_hf_sc_sos, diff, zi=self.preemph_hf_sc_zi_diff
        )
        hf_peak = max(
            float(np.max(np.abs(hf_sum))) if hf_sum.size else 0.0,
            float(np.max(np.abs(hf_diff))) if hf_diff.size else 0.0,
        )
        # Smooth sidechain level and add hysteresis/hold to prevent fast chatter on sustained HF.
        rise_tau_s = 0.006
        fall_tau_s = 0.200
        tau_s = rise_tau_s if hf_peak > self.preemph_hf_level_est else fall_tau_s
        alpha = 1.0 - math.exp(-block_time_s / max(1e-6, tau_s))
        self.preemph_hf_level_est += (hf_peak - self.preemph_hf_level_est) * alpha

        threshold_on = threshold
        threshold_off = threshold * 0.92
        hold_time_s = 0.035
        if self.preemph_hf_level_est >= threshold_on:
            self.preemph_hf_hold_s = hold_time_s
        else:
            self.preemph_hf_hold_s = max(0.0, self.preemph_hf_hold_s - block_time_s)
        active = self.preemph_hf_level_est >= threshold_off or self.preemph_hf_hold_s > 0.0

        if not active:
            target_gain = 1.0
        else:
            over_db = 20.0 * math.log10(max(self.preemph_hf_level_est, 1e-9) / threshold_on)
            reduction_db = min(max_reduction_db, max(0.0, over_db))
            target_gain = 10 ** (-reduction_db / 20.0)
        self.preemph_hf_gain = self._smooth_gain(
            self.preemph_hf_gain,
            target_gain,
            baseband.shape[0],
            attack_ms=attack_ms,
            release_ms=release_ms,
            sample_rate=self.proc_rate,
        )
        gain = max(10 ** (-max_reduction_db / 20.0), min(1.0, self.preemph_hf_gain))
        if gain >= 0.999:
            return baseband, diff
        return (baseband * gain).astype(self.dtype, copy=False), (diff * gain).astype(
            self.dtype, copy=False
        )

    def _apply_preemphasis_drive_guard(self, baseband, diff):
        if not baseband.size or not diff.size:
            return baseband, diff
        peak = max(float(np.max(np.abs(baseband))), float(np.max(np.abs(diff))), 1e-9)
        target_gain = min(1.0, 0.9 / peak)
        self.preemph_drive_gain = self._smooth_gain(
            self.preemph_drive_gain,
            target_gain,
            baseband.shape[0],
            attack_ms=1.5,
            release_ms=220.0,
            sample_rate=self.proc_rate,
        )
        gain = max(0.70, min(1.0, self.preemph_drive_gain))
        if gain >= 0.999:
            return baseband, diff
        return (baseband * gain).astype(self.dtype, copy=False), (diff * gain).astype(
            self.dtype, copy=False
        )

    def _process_stereo_audio_domain(self, left, right, proc_frames, bypass):
        if bypass:
            return self._apply_lpf(left, right)
        self._refresh_hpf()
        self._refresh_hf_trim()
        self._refresh_orbass()
        left, right = self._apply_wideband_agc(left, right)
        left, right = self._apply_hpf(left, right)
        left, right = self._apply_lpf(left, right)
        left, right = self._apply_hf_trim(left, right)
        left, right = self._apply_pilot_notch(left, right)
        left, right = self._apply_orbass(left, right)
        left, right = self._apply_multiband(left, right, proc_frames)
        left, right = self._apply_widener(left, right)
        return left, right

    def _refresh_preemphasis(self):
        try:
            current = int(mpx_state.get("preemphasis_us", 0))
        except (TypeError, ValueError):
            current = 0
        if current != self.preemphasis_us:
            self.preemphasis_us = current
            self.pre_b, self.pre_a = self._preemphasis_coeffs(self.preemphasis_us, self.proc_rate)
            if len(self.pre_b) > 1 or len(self.pre_a) > 1:
                self.pre_zi_sum = (dsp_signal.lfilter_zi(self.pre_b, self.pre_a) * 0).astype(
                    self.dtype
                )
                self.pre_zi_diff = (dsp_signal.lfilter_zi(self.pre_b, self.pre_a) * 0).astype(
                    self.dtype
                )
            else:
                self.pre_zi_sum = np.zeros(0, dtype=self.dtype)
                self.pre_zi_diff = np.zeros(0, dtype=self.dtype)

    def _apply_preemphasis(self, baseband, diff):
        baseband, self.pre_zi_sum = dsp_signal.lfilter(
            self.pre_b, self.pre_a, baseband, zi=self.pre_zi_sum
        )
        diff, self.pre_zi_diff = dsp_signal.lfilter(
            self.pre_b, self.pre_a, diff, zi=self.pre_zi_diff
        )
        return baseband, diff

    def _apply_composite_clipper(self, mpx, threshold):
        return self._oversampled_soft_clip(mpx, threshold, "_composite_pad")

    def _oversampled_soft_clip(self, signal, threshold, pad_attr, os_factor=2, pad_len=96):
        if threshold <= 0 or not signal.size:
            return signal
        if os_factor <= 1:
            return self._apply_threshold_soft_knee(signal, threshold).astype(self.dtype, copy=False)
        pad = getattr(self, pad_attr, None)
        if pad is None or pad.shape[0] != pad_len:
            pad = np.zeros(pad_len, dtype=self.dtype)
        combined = np.concatenate((pad, signal))
        target_len = combined.shape[0]
        up_window = self._get_resample_window(os_factor, 1)
        down_window = self._get_resample_window(1, os_factor)
        oversampled = dsp_signal.resample_poly(combined, os_factor, 1, window=up_window)
        oversampled = self._apply_threshold_soft_knee(oversampled, threshold)
        resampled = dsp_signal.resample_poly(oversampled, 1, os_factor, window=down_window)
        if resampled.shape[0] > target_len:
            resampled = resampled[:target_len]
        elif resampled.shape[0] < target_len:
            resampled = np.pad(resampled, (0, target_len - resampled.shape[0]))
        result = resampled[pad_len:]
        setattr(self, pad_attr, signal[-pad_len:].copy() if signal.shape[0] >= pad_len else pad)
        return result.astype(self.dtype, copy=False)

    def _apply_audio_mpx_lpf(self, mpx):
        if not mpx.size:
            return mpx
        if not bool(mpx_state.get("mpx_lpf_enabled", True)):
            return mpx
        mpx, self.audio_mpx_lpf_zi = dsp_signal.sosfilt(
            self.audio_mpx_lpf_sos, mpx, zi=self.audio_mpx_lpf_zi
        )
        return mpx

    def _apply_threshold_soft_knee(self, signal: np.ndarray, threshold: float) -> np.ndarray:
        if threshold <= 0.0:
            return signal
        if threshold >= 1.0:
            return np.clip(signal, -1.0, 1.0)
        knee = max(1e-6, 1.0 - threshold)
        abs_sig = np.abs(signal)
        over = np.maximum(abs_sig - threshold, 0.0)
        shaped_abs = np.where(
            abs_sig <= threshold,
            abs_sig,
            threshold + (knee * np.tanh(over / knee)),
        )
        return np.sign(signal) * shaped_abs

    def _compressor_level_db_ctrl(
        self,
        left: np.ndarray,
        right: np.ndarray,
        detector_hop: int,
        sc_state: float,
        rms_ms: float = 12.0,
    ) -> tuple[np.ndarray, float]:
        if not left.size or not right.size:
            return np.zeros(0, dtype=self.dtype), float(max(1e-12, sc_state))
        power = ((left * left) + (right * right)) * 0.5
        power_ctrl = power[::detector_hop]
        if not power_ctrl.size:
            return np.zeros(0, dtype=self.dtype), float(max(1e-12, sc_state))
        detector_rate = float(self.proc_rate) / float(max(1, detector_hop))
        tau_s = max(0.001, float(rms_ms) / 1000.0)
        coeff = math.exp(-1.0 / (detector_rate * tau_s))
        state = float(max(1e-12, sc_state))
        out = np.empty_like(power_ctrl, dtype=self.dtype)
        for i, p in enumerate(power_ctrl):
            state = (coeff * state) + ((1.0 - coeff) * float(p))
            out[i] = 10.0 * math.log10(max(state, 1e-12))
        return out, state

    def _compressor_gr_curve_db(
        self, level_db_ctrl: np.ndarray, threshold_db: float, ratio: float, knee_db: float
    ) -> np.ndarray:
        if ratio <= 1.0 or not level_db_ctrl.size:
            return np.zeros_like(level_db_ctrl, dtype=self.dtype)
        over_db = level_db_ctrl - threshold_db
        slope = 1.0 - (1.0 / max(1.0, float(ratio)))
        knee_db = max(0.0, min(24.0, float(knee_db)))
        if knee_db <= 1e-6:
            return np.maximum(0.0, over_db * slope).astype(self.dtype, copy=False)
        half_knee = knee_db * 0.5
        gr_db = np.zeros_like(over_db, dtype=self.dtype)
        above = over_db >= half_knee
        if np.any(above):
            gr_db[above] = (over_db[above] * slope).astype(self.dtype, copy=False)
        in_knee = (over_db > -half_knee) & (~above)
        if np.any(in_knee):
            x = over_db[in_knee] + half_knee
            gr_db[in_knee] = (slope * ((x * x) / (2.0 * knee_db))).astype(self.dtype, copy=False)
        return np.maximum(gr_db, 0.0).astype(self.dtype, copy=False)

    def _apply_gr_envelope_and_gain(
        self,
        left: np.ndarray,
        right: np.ndarray,
        target_gr_db_ctrl: np.ndarray,
        attack_ms: float,
        release_ms: float,
        gr_state_db: float,
        detector_hop: int,
        release_scale: float = 1.0,
    ) -> tuple[np.ndarray, np.ndarray, float]:
        if not left.size or not right.size:
            return left, right, gr_state_db
        if target_gr_db_ctrl.size == 0:
            return left, right, gr_state_db
        attack_ms = max(0.0, float(attack_ms))
        release_scale = max(0.9, min(1.15, float(release_scale)))
        release_ms = max(0.0, float(release_ms) * release_scale)
        detector_rate = float(self.proc_rate) / float(max(1, detector_hop))
        if attack_ms <= 0.0:
            attack_coeff = 0.0
        else:
            attack_coeff = math.exp(-1.0 / (detector_rate * (attack_ms / 1000.0)))
        if release_ms <= 0.0:
            release_coeff_fast = 0.0
            release_coeff_slow = 0.0
        else:
            release_fast_ms = max(10.0, release_ms * 0.40)
            release_slow_ms = max(release_fast_ms + 10.0, release_ms * 2.20)
            release_coeff_fast = math.exp(-1.0 / (detector_rate * (release_fast_ms / 1000.0)))
            release_coeff_slow = math.exp(-1.0 / (detector_rate * (release_slow_ms / 1000.0)))
        state = max(0.0, float(gr_state_db))
        if state <= 1e-9:
            state = float(target_gr_db_ctrl[0])
        gr_ctrl = np.empty_like(target_gr_db_ctrl, dtype=self.dtype)
        for i, target in enumerate(target_gr_db_ctrl):
            target_f = float(target)
            if target_f > state:
                coeff = attack_coeff
            else:
                release_delta_db = max(0.0, state - target_f)
                # Program-dependent release: fast away from transients, slower near the floor.
                fast_mix = max(0.0, min(1.0, (release_delta_db - 0.5) / 8.0))
                coeff = (release_coeff_slow * (1.0 - fast_mix)) + (release_coeff_fast * fast_mix)
            state = (coeff * state) + ((1.0 - coeff) * float(target))
            gr_ctrl[i] = state
        if detector_hop > 1:
            gr_db = np.repeat(gr_ctrl, detector_hop)[: left.shape[0]]
        else:
            gr_db = gr_ctrl
        gain = np.power(10.0, (-gr_db / 20.0)).astype(self.dtype, copy=False)
        return (left * gain).astype(self.dtype, copy=False), (
            right * gain
        ).astype(self.dtype, copy=False), float(state)

    def _apply_widener(self, left, right):
        if not bool(mpx_state.get("stereo_widen_enabled")):
            return left, right
        if not left.size or not right.size:
            return left, right
        width = float(mpx_state.get("stereo_widen_width", 0.5))
        center = float(mpx_state.get("stereo_widen_center", 0.5))
        mix = float(mpx_state.get("stereo_widen_mix", 1.0))
        width = max(0.0, min(1.0, width))
        center = max(0.0, min(1.0, center))
        mix = max(0.0, min(1.0, mix))
        target_side_gain = width * 2.0
        target_mid_gain = center * 2.0
        target_mix = mix
        block_time_s = float(left.shape[0]) / max(1.0, float(self.proc_rate))
        smooth_tau_s = 0.08
        alpha = 1.0 - math.exp(-block_time_s / smooth_tau_s)
        self.widen_side_gain += (target_side_gain - self.widen_side_gain) * alpha
        self.widen_mid_gain += (target_mid_gain - self.widen_mid_gain) * alpha
        self.widen_mix += (target_mix - self.widen_mix) * alpha
        side_gain = max(0.0, self.widen_side_gain)
        mid_gain = max(0.0, self.widen_mid_gain)
        wet_mix = max(0.0, min(1.0, self.widen_mix))
        # Energy normalization keeps loudness steadier when width/center are adjusted live.
        norm = math.sqrt(max(1e-6, ((mid_gain * mid_gain) + (side_gain * side_gain)) * 0.5))
        mid = (left + right) * 0.5
        side = (left - right) * 0.5
        wet_l = ((mid * mid_gain) + (side * side_gain)) / norm
        wet_r = ((mid * mid_gain) - (side * side_gain)) / norm
        out_l = (left * (1.0 - wet_mix)) + (wet_l * wet_mix)
        out_r = (right * (1.0 - wet_mix)) + (wet_r * wet_mix)
        return out_l.astype(self.dtype, copy=False), out_r.astype(self.dtype, copy=False)

    def _mb_lerp(self, a: float, b: float, t: float) -> float:
        tt = max(0.0, min(1.0, float(t)))
        return (a * (1.0 - tt)) + (b * tt)

    def _band_release_scale(self, band_l: np.ndarray, band_r: np.ndarray) -> float:
        if not band_l.size or not band_r.size:
            return 1.0
        rms = float(np.sqrt((np.mean(band_l * band_l) + np.mean(band_r * band_r)) * 0.5))
        if rms <= 1e-9:
            return 1.0
        peak = max(float(np.max(np.abs(band_l))), float(np.max(np.abs(band_r))))
        crest_db = 20.0 * math.log10(max(peak, 1e-9) / rms)
        return max(0.9, min(1.15, 0.95 + (0.015 * crest_db)))

    def _apply_multiband(self, left, right, frames):
        if not bool(mpx_state.get("multiband_enabled")):
            return left, right
        self._refresh_multiband_filters()
        threshold_low = float(mpx_state.get("multiband_low_threshold_db", 0.0))
        threshold_mid = float(mpx_state.get("multiband_mid_threshold_db", 0.0))
        threshold_high = float(mpx_state.get("multiband_high_threshold_db", 0.0))
        ratio_low = float(mpx_state.get("multiband_low_ratio", 3.0))
        ratio_mid = float(mpx_state.get("multiband_mid_ratio", 3.0))
        ratio_high = float(mpx_state.get("multiband_high_ratio", 3.0))
        attack_low = float(mpx_state.get("multiband_low_attack_ms", 50.0))
        attack_mid = float(mpx_state.get("multiband_mid_attack_ms", 50.0))
        attack_high = float(mpx_state.get("multiband_high_attack_ms", 50.0))
        release_low = float(mpx_state.get("multiband_low_release_ms", 250.0))
        release_mid = float(mpx_state.get("multiband_mid_release_ms", 250.0))
        release_high = float(mpx_state.get("multiband_high_release_ms", 250.0))
        knee_db = max(0.0, min(12.0, float(mpx_state.get("multiband_knee_db", 2.0))))
        link_strength = max(0.0, min(1.0, float(mpx_state.get("multiband_link_strength", 0.22))))
        release_program_dependent = bool(mpx_state.get("multiband_release_program_dependent", True))
        detector_hop = max(1, min(8, int(self.proc_rate // 48000)))
        if self.mb_mode == 5:
            b1_l, self.mb5_lp1_zi_l = dsp_signal.sosfilt(self.mb5_lp1_sos, left, zi=self.mb5_lp1_zi_l)
            b1_r, self.mb5_lp1_zi_r = dsp_signal.sosfilt(
                self.mb5_lp1_sos, right, zi=self.mb5_lp1_zi_r
            )
            rem1_l = left - b1_l
            rem1_r = right - b1_r
            b2_l, self.mb5_lp2_zi_l = dsp_signal.sosfilt(self.mb5_lp2_sos, rem1_l, zi=self.mb5_lp2_zi_l)
            b2_r, self.mb5_lp2_zi_r = dsp_signal.sosfilt(
                self.mb5_lp2_sos, rem1_r, zi=self.mb5_lp2_zi_r
            )
            rem2_l = rem1_l - b2_l
            rem2_r = rem1_r - b2_r
            b3_l, self.mb5_lp3_zi_l = dsp_signal.sosfilt(self.mb5_lp3_sos, rem2_l, zi=self.mb5_lp3_zi_l)
            b3_r, self.mb5_lp3_zi_r = dsp_signal.sosfilt(
                self.mb5_lp3_sos, rem2_r, zi=self.mb5_lp3_zi_r
            )
            rem3_l = rem2_l - b3_l
            rem3_r = rem2_r - b3_r
            b4_l, self.mb5_lp4_zi_l = dsp_signal.sosfilt(self.mb5_lp4_sos, rem3_l, zi=self.mb5_lp4_zi_l)
            b4_r, self.mb5_lp4_zi_r = dsp_signal.sosfilt(
                self.mb5_lp4_sos, rem3_r, zi=self.mb5_lp4_zi_r
            )
            b5_l = rem3_l - b4_l
            b5_r = rem3_r - b4_r
            thresholds = [
                threshold_low,
                self._mb_lerp(threshold_low, threshold_mid, 0.5),
                threshold_mid,
                self._mb_lerp(threshold_mid, threshold_high, 0.5),
                threshold_high,
            ]
            ratios = [
                ratio_low,
                self._mb_lerp(ratio_low, ratio_mid, 0.5),
                ratio_mid,
                self._mb_lerp(ratio_mid, ratio_high, 0.5),
                ratio_high,
            ]
            attacks = [
                attack_low,
                self._mb_lerp(attack_low, attack_mid, 0.5),
                attack_mid,
                self._mb_lerp(attack_mid, attack_high, 0.5),
                attack_high,
            ]
            releases = [
                release_low,
                self._mb_lerp(release_low, release_mid, 0.5),
                release_mid,
                self._mb_lerp(release_mid, release_high, 0.5),
                release_high,
            ]
            bands_l = [b1_l, b2_l, b3_l, b4_l, b5_l]
            bands_r = [b1_r, b2_r, b3_r, b4_r, b5_r]
            release_scales = [1.0] * 5
            if release_program_dependent:
                release_scales = [
                    self._band_release_scale(bands_l[i], bands_r[i]) for i in range(5)
                ]
            target_gr = []
            for i in range(5):
                level_db, self.mb5_sc[i] = self._compressor_level_db_ctrl(
                    bands_l[i], bands_r[i], detector_hop, self.mb5_sc[i], rms_ms=12.0
                )
                target_gr.append(
                    self._compressor_gr_curve_db(level_db, thresholds[i], ratios[i], knee_db)
                )
            if link_strength > 1e-4:
                linked = np.maximum.reduce(target_gr)
                target_gr = [
                    ((1.0 - link_strength) * target_gr[i]) + (link_strength * linked) for i in range(5)
                ]
            for i in range(5):
                bands_l[i], bands_r[i], self.mb5_env[i] = self._apply_gr_envelope_and_gain(
                    bands_l[i],
                    bands_r[i],
                    target_gr[i],
                    attacks[i],
                    releases[i],
                    self.mb5_env[i],
                    detector_hop,
                    release_scale=release_scales[i],
                )
            out_l = bands_l[0] + bands_l[1] + bands_l[2] + bands_l[3] + bands_l[4]
            out_r = bands_r[0] + bands_r[1] + bands_r[2] + bands_r[3] + bands_r[4]
            return out_l.astype(self.dtype, copy=False), out_r.astype(self.dtype, copy=False)

        low_l, self.mb_lp1_zi_l = dsp_signal.sosfilt(self.mb_lp1_sos, left, zi=self.mb_lp1_zi_l)
        low_r, self.mb_lp1_zi_r = dsp_signal.sosfilt(self.mb_lp1_sos, right, zi=self.mb_lp1_zi_r)
        rem_l = left - low_l
        rem_r = right - low_r
        mid_l, self.mb_lp2_zi_l = dsp_signal.sosfilt(self.mb_lp2_sos, rem_l, zi=self.mb_lp2_zi_l)
        mid_r, self.mb_lp2_zi_r = dsp_signal.sosfilt(self.mb_lp2_sos, rem_r, zi=self.mb_lp2_zi_r)
        high_l = rem_l - mid_l
        high_r = rem_r - mid_r
        rel_scale_low = 1.0
        rel_scale_mid = 1.0
        rel_scale_high = 1.0
        if release_program_dependent:
            rel_scale_low = self._band_release_scale(low_l, low_r)
            rel_scale_mid = self._band_release_scale(mid_l, mid_r)
            rel_scale_high = self._band_release_scale(high_l, high_r)
        level_low_db, self.mb_sc_low = self._compressor_level_db_ctrl(
            low_l, low_r, detector_hop, self.mb_sc_low, rms_ms=12.0
        )
        level_mid_db, self.mb_sc_mid = self._compressor_level_db_ctrl(
            mid_l, mid_r, detector_hop, self.mb_sc_mid, rms_ms=12.0
        )
        level_high_db, self.mb_sc_high = self._compressor_level_db_ctrl(
            high_l, high_r, detector_hop, self.mb_sc_high, rms_ms=12.0
        )
        target_low = self._compressor_gr_curve_db(level_low_db, threshold_low, ratio_low, knee_db)
        target_mid = self._compressor_gr_curve_db(level_mid_db, threshold_mid, ratio_mid, knee_db)
        target_high = self._compressor_gr_curve_db(level_high_db, threshold_high, ratio_high, knee_db)
        if link_strength > 1e-4:
            linked = np.maximum.reduce([target_low, target_mid, target_high])
            target_low = ((1.0 - link_strength) * target_low) + (link_strength * linked)
            target_mid = ((1.0 - link_strength) * target_mid) + (link_strength * linked)
            target_high = ((1.0 - link_strength) * target_high) + (link_strength * linked)
        low_l, low_r, self.mb_env_low = self._apply_gr_envelope_and_gain(
            low_l,
            low_r,
            target_low,
            attack_low,
            release_low,
            self.mb_env_low,
            detector_hop,
            release_scale=rel_scale_low,
        )
        mid_l, mid_r, self.mb_env_mid = self._apply_gr_envelope_and_gain(
            mid_l,
            mid_r,
            target_mid,
            attack_mid,
            release_mid,
            self.mb_env_mid,
            detector_hop,
            release_scale=rel_scale_mid,
        )
        high_l, high_r, self.mb_env_high = self._apply_gr_envelope_and_gain(
            high_l,
            high_r,
            target_high,
            attack_high,
            release_high,
            self.mb_env_high,
            detector_hop,
            release_scale=rel_scale_high,
        )
        out_l = low_l + mid_l + high_l
        out_r = low_r + mid_r + high_r
        return out_l.astype(self.dtype, copy=False), out_r.astype(self.dtype, copy=False)

    def _resample(self, data, up, down, target_len):
        if up == down or not data.size:
            return data
        window = self._get_resample_window(up, down)
        resampled = dsp_signal.resample_poly(data, up, down, axis=0, window=window)
        current_len = resampled.shape[0]
        if target_len is not None:
            if current_len > target_len:
                resampled = resampled[:target_len]
            elif current_len < target_len:
                pad_shape = [(0, 0)] * resampled.ndim
                pad_shape[0] = (0, target_len - current_len)
                resampled = np.pad(resampled, pad_shape)
        return resampled.astype(self.dtype, copy=False)

    def _apply_audio_headroom(self, audio, carriers, threshold):
        if threshold <= 0 or not audio.size:
            return audio, 1.0
        abs_audio = np.abs(audio)
        abs_carriers = np.abs(carriers)
        margin = threshold - abs_carriers
        if np.any(margin <= 0):
            return audio * 0.0, 0.0
        mask = abs_audio > 1e-9
        if not np.any(mask):
            return audio, 1.0
        target_gain = float(np.min(margin[mask] / abs_audio[mask]))
        target_gain = max(0.0, min(1.0, target_gain))
        # Fast-but-smoothed gain control avoids audible zipper/click artifacts under protection.
        self.audio_headroom_gain = self._smooth_gain(
            self.audio_headroom_gain,
            target_gain,
            audio.shape[0],
            attack_ms=1.5,
            release_ms=80.0,
        )
        gain = max(0.0, min(1.0, self.audio_headroom_gain))
        return audio * gain, gain

    def _apply_smoothed_peak_trim(
        self,
        signal: np.ndarray,
        threshold: float,
        gain_attr: str,
        attack_ms: float = 1.5,
        release_ms: float = 80.0,
    ) -> tuple[np.ndarray, bool]:
        if threshold <= 0.0 or not signal.size:
            return signal, False
        peak = float(np.max(np.abs(signal)))
        target_gain = min(1.0, threshold / peak) if peak > 1e-9 else 1.0
        current_gain = float(getattr(self, gain_attr, 1.0))
        next_gain = self._smooth_gain(
            current_gain,
            target_gain,
            signal.shape[0],
            attack_ms=attack_ms,
            release_ms=release_ms,
            sample_rate=self.sample_rate,
        )
        setattr(self, gain_attr, next_gain)
        applied_gain = max(0.0, min(1.0, next_gain))
        return signal * applied_gain, (target_gain < 0.999 or applied_gain < 0.999)

    def _reset_dsp_state(self):
        self.mb_env_low = 0.0
        self.mb_env_mid = 0.0
        self.mb_env_high = 0.0
        self.mb_sc_low = 1e-9
        self.mb_sc_mid = 1e-9
        self.mb_sc_high = 1e-9
        self.mb5_env = [0.0] * 5
        self.mb5_sc = [1e-9] * 5
        self.agc_gain = 1.0
        self.agc_initialized = False
        self._init_orbass()
        self._init_preemphasis_hf_control()
        self._init_multiband_filters()
        self.widen_side_gain = 1.0
        self.widen_mid_gain = 1.0
        self.widen_mix = 1.0
        self.composite_limit_gain = 1.0
        self.composite_clip_trim_gain = 1.0
        self.composite_safety_gain = 1.0
        self.preemph_drive_gain = 1.0
        self._init_lookahead_state()
        self.audio_headroom_gain = 1.0
        for name in ("_preemph_sum_pad", "_preemph_diff_pad", "_composite_pad"):
            if hasattr(self, name):
                delattr(self, name)
        zi_names = (
            "audio_lpf_zi_l",
            "audio_lpf_zi_r",
            "audio_notch_zi_l",
            "audio_notch_zi_r",
            "hpf_zi_l",
            "hpf_zi_r",
            "hf_zi_l",
            "hf_zi_r",
            "pre_zi_sum",
            "pre_zi_diff",
            "mb_lp1_zi_l",
            "mb_lp1_zi_r",
            "mb_hp1_zi_l",
            "mb_hp1_zi_r",
            "mb_lp2_zi_l",
            "mb_lp2_zi_r",
            "mb_hp2_zi_l",
            "mb_hp2_zi_r",
            "mb5_lp1_zi_l",
            "mb5_lp1_zi_r",
            "mb5_hp1_zi_l",
            "mb5_hp1_zi_r",
            "mb5_lp2_zi_l",
            "mb5_lp2_zi_r",
            "mb5_hp2_zi_l",
            "mb5_hp2_zi_r",
            "mb5_lp3_zi_l",
            "mb5_lp3_zi_r",
            "mb5_hp3_zi_l",
            "mb5_hp3_zi_r",
            "mb5_lp4_zi_l",
            "mb5_lp4_zi_r",
            "mb5_hp4_zi_l",
            "mb5_hp4_zi_r",
            "bpf_zi",
            "audio_mpx_lpf_zi",
            "mpx_dc_zi",
            "mpx_notch_zi",
            "mon_lpf_zi",
            "mon_lpf_zi_diff",
            "mon_bpf_zi",
            "de_zi_l",
            "de_zi_r",
            "preemph_hf_sc_zi_sum",
            "preemph_hf_sc_zi_diff",
        )
        for name in zi_names:
            if hasattr(self, name):
                state = getattr(self, name)
                try:
                    setattr(self, name, np.zeros_like(state))
                except Exception:
                    continue

    def _apply_lookahead_limiter_named(
        self, signal, threshold, state_prefix, sample_rate=None
    ):
        if threshold <= 0:
            return signal, False
        if sample_rate is None:
            sample_rate = self.sample_rate
        try:
            la_ms = float(mpx_state.get("limit_lookahead_ms", 5.0))
        except (TypeError, ValueError):
            la_ms = 5.0
        la_ms = max(0.0, min(20.0, la_ms))
        la_samples = max(1, int(float(sample_rate) * la_ms / 1000.0))
        samples_attr = f"{state_prefix}_samples"
        buffer_attr = f"{state_prefix}_buffer"
        gain_attr = f"{state_prefix}_gain"
        current_samples = int(getattr(self, samples_attr, 0))
        buffer_state = getattr(self, buffer_attr, None)
        if buffer_state is None or la_samples != current_samples:
            seed = float(signal[0]) if signal.size else 0.0
            setattr(self, samples_attr, la_samples)
            setattr(self, buffer_attr, np.full(la_samples, seed, dtype=self.dtype))
            setattr(self, gain_attr, 1.0)
            buffer_state = getattr(self, buffer_attr)
        combined = np.concatenate((buffer_state, signal))
        delayed = combined[: signal.shape[0]]
        # Compute gain from delayed+future content, then apply to delayed program.
        window_peak = float(np.max(np.abs(combined))) if combined.size else 0.0
        target_gain = min(1.0, threshold / window_peak) if window_peak > 1e-6 else 1.0
        attack_ms = 2.0
        release_ms = 60.0
        frames = signal.shape[0]
        gain_state = float(getattr(self, gain_attr, 1.0))
        gain_state = self._smooth_gain(
            gain_state,
            target_gain,
            frames,
            attack_ms,
            release_ms,
            sample_rate=sample_rate,
        )
        setattr(self, gain_attr, gain_state)
        limited = delayed * gain_state
        setattr(self, buffer_attr, combined[frames : frames + la_samples].copy())
        return limited.astype(self.dtype, copy=False), (target_gain < 0.999 or gain_state < 0.999)

    def _apply_lookahead_limiter_pair(
        self, signal_a, signal_b, threshold, state_prefix, sample_rate=None
    ):
        if threshold <= 0 or signal_a.shape[0] != signal_b.shape[0]:
            return signal_a, signal_b, False
        if sample_rate is None:
            sample_rate = self.proc_rate
        try:
            la_ms = float(mpx_state.get("limit_lookahead_ms", 5.0))
        except (TypeError, ValueError):
            la_ms = 5.0
        la_ms = max(0.0, min(20.0, la_ms))
        la_samples = max(1, int(float(sample_rate) * la_ms / 1000.0))
        samples_attr = f"{state_prefix}_samples"
        buffer_attr = f"{state_prefix}_buffer"
        gain_attr = f"{state_prefix}_gain"
        current_samples = int(getattr(self, samples_attr, 0))
        buffer_state = getattr(self, buffer_attr, None)
        if (
            buffer_state is None
            or la_samples != current_samples
            or len(buffer_state.shape) != 2
            or buffer_state.shape[1] != 2
        ):
            if signal_a.size:
                seed_row = np.array([signal_a[0], signal_b[0]], dtype=self.dtype)
            else:
                seed_row = np.zeros(2, dtype=self.dtype)
            setattr(self, samples_attr, la_samples)
            setattr(self, buffer_attr, np.tile(seed_row, (la_samples, 1)))
            setattr(self, gain_attr, 1.0)
            buffer_state = getattr(self, buffer_attr)
        block = np.column_stack((signal_a, signal_b)).astype(self.dtype, copy=False)
        combined = np.vstack((buffer_state, block))
        delayed_block = combined[: signal_a.shape[0], :]
        window_peak = float(np.max(np.abs(combined))) if combined.size else 0.0
        target_gain = min(1.0, threshold / window_peak) if window_peak > 1e-6 else 1.0
        attack_ms = 2.0
        release_ms = 60.0
        frames = signal_a.shape[0]
        gain_state = float(getattr(self, gain_attr, 1.0))
        gain_state = self._smooth_gain(
            gain_state,
            target_gain,
            frames,
            attack_ms,
            release_ms,
            sample_rate=sample_rate,
        )
        setattr(self, gain_attr, gain_state)
        limited_block = delayed_block * gain_state
        setattr(self, buffer_attr, combined[frames : frames + la_samples].copy())
        return (
            limited_block[:, 0].astype(self.dtype, copy=False),
            limited_block[:, 1].astype(self.dtype, copy=False),
            (target_gain < 0.999 or gain_state < 0.999),
        )

    def _process_frame(self, outdata, frames, indata):
        if dsp_control.get("reset"):
            self._reset_dsp_state()
            dsp_control["reset"] = False
        bypass = bool(mpx_state.get("processing_bypass"))
        mono_mode = bool(mpx_state.get("mono_mode")) and not bypass
        level = float(mpx_state.get("pilot_level", 0.2))
        sum_level = float(mpx_state.get("sum_level", 0.3))
        diff_level = float(mpx_state.get("diff_level", 0.3))
        tone_freq = float(mpx_state.get("test_tone_freq", 1000.0))
        input_gain_db = float(mpx_state.get("input_gain_db", 0.0))
        input_gain = 10 ** (input_gain_db / 20.0) if input_gain_db else 1.0
        proc_rate = self.proc_rate
        proc_frames = frames
        up = down = 1
        if proc_rate != self.sample_rate:
            proc_frames = max(1, int(round(frames * proc_rate / self.sample_rate)))
            g = math.gcd(self.sample_rate, proc_rate)
            down = self.sample_rate // g
            up = proc_rate // g
        t = self._get_time_base(frames, self.sample_rate) + self.phase
        pilot = np.sin(2 * np.pi * PILOT_FREQ * t) * level
        input_rms = 0.0
        input_peak = 0.0
        input_pre_rms = 0.0
        input_pre_peak = 0.0
        indata_stereo = None
        scope_left = None
        scope_right = None
        if indata is not None and indata.shape[0] == frames:
            if indata.shape[1] >= 2:
                indata_stereo = indata[:, :2]
            elif indata.shape[1] == 1:
                indata_stereo = np.column_stack((indata[:, 0], indata[:, 0]))

        if mpx_state.get("source_mode") == "input" and mpx_state.get("device_in_idx", -1) >= 0:
            if indata_stereo is not None:
                if self.audio_in:
                    self.audio_in.stop()
                    self.audio_in = None
                stereo = np.array(indata_stereo, dtype=self.dtype, copy=True)
                input_pre_rms = float(np.sqrt(np.mean(stereo**2))) if stereo.size else 0.0
                input_pre_peak = float(np.max(np.abs(stereo))) if stereo.size else 0.0
                if input_gain != 1.0:
                    stereo = stereo * input_gain
                if proc_rate != self.sample_rate:
                    stereo = self._resample(stereo, up, down, proc_frames)
                left = stereo[:, 0]
                right = stereo[:, 1]
                left, right = self._process_stereo_audio_domain(left, right, proc_frames, bypass)
                if left.size and right.size:
                    input_rms = float(
                        np.sqrt((np.mean(left**2) + np.mean(right**2)) * 0.5)
                    )
                    input_peak = max(float(np.max(np.abs(left))), float(np.max(np.abs(right))))
                else:
                    input_rms = 0.0
                    input_peak = 0.0
                scope_left = left
                scope_right = right
                baseband = (left + right) * 0.5 * sum_level
                diff = (right - left) * 0.5 * diff_level
            else:
                if not self.audio_in or self.audio_in.device_idx != mpx_state.get("device_in_idx"):
                    if self.audio_in:
                        self.audio_in.stop()
                    self.audio_in = AudioInputReader(
                        mpx_state["device_in_idx"],
                        self.sample_rate,
                        self.dtype,
                        blocksize=self.blocksize,
                    )
                    self.audio_in.start()
                    if not self.logged_input_fallback:
                        logger.warning(
                            "StereoFool: duplex input unavailable, using separate input stream"
                        )
                        self.logged_input_fallback = True
                prebuffer_frames = int(PREBUFFER_SECONDS * self.sample_rate)
                if self.audio_in.buffered_frames() < prebuffer_frames:
                    baseband = self._get_zeros(proc_frames)
                    diff = self._get_zeros(proc_frames)
                else:
                    stereo = self.audio_in.read_frames_clock_adaptive(frames)
                    input_pre_rms = float(np.sqrt(np.mean(stereo**2))) if stereo.size else 0.0
                    input_pre_peak = float(np.max(np.abs(stereo))) if stereo.size else 0.0
                    if input_gain != 1.0:
                        stereo = stereo * input_gain
                    if proc_rate != self.sample_rate:
                        stereo = self._resample(stereo, up, down, proc_frames)
                    left = stereo[:, 0]
                    right = stereo[:, 1]
                    left, right = self._process_stereo_audio_domain(left, right, proc_frames, bypass)
                    if left.size and right.size:
                        input_rms = float(
                            np.sqrt((np.mean(left**2) + np.mean(right**2)) * 0.5)
                        )
                        input_peak = max(
                            float(np.max(np.abs(left))), float(np.max(np.abs(right)))
                        )
                    else:
                        input_rms = 0.0
                        input_peak = 0.0
                    scope_left = left
                    scope_right = right
                    baseband = (left + right) * 0.5 * sum_level
                    diff = (right - left) * 0.5 * diff_level

        else:
            tone_t = self._get_time_base(proc_frames, proc_rate) + self.tone_phase
            tone = np.sin(2 * np.pi * tone_freq * tone_t)
            mode = mpx_state.get("test_tone_mode", "mono")
            if mode == "left":
                left = tone * sum_level
                right = self._get_zeros(proc_frames)
            elif mode == "right":
                left = self._get_zeros(proc_frames)
                right = tone * sum_level
            elif mode == "stereo":
                left = tone * sum_level
                right = -tone * sum_level
            else:
                left = tone * sum_level
                right = tone * sum_level
            if input_gain != 1.0:
                left = left * input_gain
                right = right * input_gain
            if left.size and right.size:
                input_pre_rms = float(np.sqrt((np.mean(left**2) + np.mean(right**2)) * 0.5))
                input_pre_peak = max(float(np.max(np.abs(left))), float(np.max(np.abs(right))))
            else:
                input_pre_rms = 0.0
                input_pre_peak = 0.0
            left, right = self._process_stereo_audio_domain(left, right, proc_frames, bypass)
            if left.size and right.size:
                input_rms = float(np.sqrt((np.mean(left**2) + np.mean(right**2)) * 0.5))
                input_peak = max(float(np.max(np.abs(left))), float(np.max(np.abs(right))))
            else:
                input_rms = 0.0
                input_peak = 0.0
            scope_left = left
            scope_right = right
            baseband = (left + right) * 0.5
            diff = (right - left) * 0.5

        if mono_mode:
            diff = np.zeros_like(diff)
        limit_enabled = bool(mpx_state.get("limit_mpx")) and not bypass
        lookahead_enabled = bool(mpx_state.get("limit_lookahead_enabled", True))
        limit_threshold = float(mpx_state.get("limit_threshold", 0.98)) if limit_enabled else 1.0
        audio_la_active = False
        self._refresh_preemphasis()
        if self.preemphasis_us:
            baseband, diff = self._apply_preemphasis(baseband, diff)
        if not bypass:
            baseband, diff = self._apply_preemphasis_hf_control(baseband, diff)
        if limit_enabled and lookahead_enabled and limit_threshold > 0:
            baseband, diff, audio_la_active = self._apply_lookahead_limiter_pair(
                baseband,
                diff,
                limit_threshold,
                "lookahead_audio_pair",
                sample_rate=self.proc_rate,
            )
        preemph_limit_enabled = bool(mpx_state.get("preemphasis_limit_enabled")) and not bypass
        preemph_limit_active = False
        if preemph_limit_enabled:
            threshold = float(mpx_state.get("preemphasis_limit_threshold", 0.95))
            preemph_peak = 0.0
            if baseband.size:
                preemph_peak = max(preemph_peak, float(np.max(np.abs(baseband))))
            if diff.size:
                preemph_peak = max(preemph_peak, float(np.max(np.abs(diff))))
            preemph_limit_active = preemph_peak > threshold
            baseband, diff, preemph_pair_active = self._apply_lookahead_limiter_pair(
                baseband,
                diff,
                threshold,
                "lookahead_preemph_pair",
                sample_rate=self.proc_rate,
            )
            if preemph_peak > threshold and not preemph_pair_active:
                scale = threshold / max(preemph_peak, 1e-9)
                baseband = baseband * scale
                diff = diff * scale
                preemph_pair_active = True
            if preemph_pair_active:
                preemph_limit_active = True
        if preemph_limit_enabled and not bypass and self.preemphasis_us:
            baseband, diff = self._apply_preemphasis_drive_guard(baseband, diff)
        elif self.preemph_drive_gain < 0.999:
            self.preemph_drive_gain = self._smooth_gain(
                self.preemph_drive_gain,
                1.0,
                baseband.shape[0],
                attack_ms=40.0,
                release_ms=80.0,
                sample_rate=self.proc_rate,
            )
        if proc_rate != self.sample_rate:
            baseband = self._resample(baseband, down, up, frames)
            diff = self._resample(diff, down, up, frames)
        subcarrier = np.sin(2 * np.pi * (2 * PILOT_FREQ) * t)
        dsb_sc = diff * subcarrier
        dsb_sc, self.bpf_zi = dsp_signal.sosfilt(self.bpf_sos, dsb_sc, zi=self.bpf_zi)

        mpx_audio = baseband + dsb_sc
        if not bypass:
            mpx_audio = self._apply_audio_mpx_lpf(mpx_audio)
            self._refresh_mpx_cleanup()
            mpx_audio = self._apply_mpx_dc_block(mpx_audio)
            mpx_audio = self._apply_mpx_notch(mpx_audio)

        en_rds = bool(mpx_state.get("en_rds"))
        if en_rds and not self.rds_enabled:
            # Reset RDS generator when re-enabled for a clean restart.
            self.rds = RDSSubcarrier(self.sample_rate)
        self.rds_enabled = en_rds

        mpx_audio = mpx_audio * (float(mpx_state.get("mpx_deviation_khz", 75.0)) / 75.0)

        pilot_sig = np.zeros_like(mpx_audio)
        if not mono_mode:
            pilot_sig = pilot

        rds_sig = np.zeros_like(mpx_audio)
        if en_rds:
            rds_sig = self.rds.synthesize(frames, self.phase).astype(self.dtype, copy=False)
        carriers = pilot_sig + rds_sig

        output_gain_db = float(mpx_state.get("output_gain_db", 0.0))
        output_gain_lin = 10 ** (output_gain_db / 20.0) if output_gain_db else 1.0
        threshold = limit_threshold if limit_enabled else 1.0
        # Reserve headroom for post-MPX output gain to avoid hidden clipping when safety limiters are off.
        threshold = threshold / max(output_gain_lin, 1e-6)
        audio_gain = 1.0
        headroom_needed = bool(limit_enabled or output_gain_lin > 1.0)
        if threshold > 0 and not bypass and headroom_needed:
            mpx_audio, audio_gain = self._apply_audio_headroom(mpx_audio, carriers, threshold)

        mpx = mpx_audio + carriers
        composite_limit_active = False
        if limit_enabled and threshold > 0:
            if lookahead_enabled:
                mpx, composite_limit_active = self._apply_lookahead_limiter_named(
                    mpx,
                    threshold,
                    "lookahead_mpx",
                    sample_rate=self.sample_rate,
                )
            else:
                mpx, composite_limit_active = self._apply_smoothed_peak_trim(
                    mpx,
                    threshold,
                    "composite_limit_gain",
                    attack_ms=1.5,
                    release_ms=70.0,
                )

        composite_clip_enabled = bool(mpx_state.get("composite_clip_enabled")) and not bypass
        composite_clip_active = False
        if composite_clip_enabled:
            comp_threshold = float(mpx_state.get("composite_clip_threshold", 0.98))
            mpx, clip_trim_active = self._apply_lookahead_limiter_named(
                mpx,
                comp_threshold,
                "lookahead_composite",
                sample_rate=self.sample_rate,
            )
            pre_clip_peak = float(np.max(np.abs(mpx))) if mpx.size else 0.0
            if pre_clip_peak > comp_threshold:
                composite_clip_active = True
                mpx = mpx * (comp_threshold / max(pre_clip_peak, 1e-9))
                if pre_clip_peak > (comp_threshold * 1.25):
                    mpx = self._apply_composite_clipper(mpx, comp_threshold)
                    clipped_peak = float(np.max(np.abs(mpx))) if mpx.size else 0.0
                    if clipped_peak > comp_threshold + 1e-4:
                        mpx = mpx * (comp_threshold / max(clipped_peak, 1e-9))
            elif clip_trim_active:
                composite_clip_active = True

        # Absolute deviation guard:
        # - If user-enabled protection is active, use smooth safety trim as last resort.
        # - Otherwise, avoid hidden gain riding and only hard-clip any out-of-range samples.
        has_dynamic_protection = bool(limit_enabled or preemph_limit_enabled or composite_clip_enabled)
        if has_dynamic_protection:
            mpx, _ = self._apply_smoothed_peak_trim(
                mpx,
                1.0,
                "composite_safety_gain",
                attack_ms=0.8,
                release_ms=140.0,
            )
            safety_peak = float(np.max(np.abs(mpx))) if mpx.size else 0.0
            if safety_peak > 1.0 + 1e-4:
                mpx = mpx * (1.0 / max(safety_peak, 1e-9))
        else:
            self.composite_safety_gain = 1.0
            if mpx.size:
                mpx = np.clip(mpx, -1.0, 1.0).astype(self.dtype, copy=False)

        limiter_active = bool(
            limit_enabled
            and (
                audio_la_active
                or preemph_limit_active
                or audio_gain < 0.999
                or composite_limit_active
            )
        )
        mpx_rms = float(np.sqrt(np.mean(mpx**2))) if mpx.size else 0.0
        mpx_peak = float(np.max(np.abs(mpx))) if mpx.size else 0.0
        mpx_pre_gain = mpx
        if output_gain_db:
            mpx = mpx * output_gain_lin
        if self.capture_callback:
            try:
                # Capture pre-output gain for accurate calibration.
                self.capture_callback(mpx_pre_gain)
            except Exception:
                pass
        if self.monitor_callback:
            try:
                mon = self._monitor_demod(mpx_pre_gain, subcarrier.astype(self.dtype, copy=False))
                if mon is not None:
                    self.monitor_callback(mon)
            except Exception:
                pass

        now = time.monotonic()
        if now - self._last_telemetry_enqueue >= self.telemetry_interval_s:
            self._enqueue_telemetry(
                {
                    "input_rms": input_rms,
                    "input_peak": input_peak,
                    "input_pre_rms": input_pre_rms,
                    "input_pre_peak": input_pre_peak,
                    "mpx_rms": mpx_rms,
                    "mpx_peak": mpx_peak,
                    "limiter_active": limiter_active,
                    "preemph_limit_enabled": preemph_limit_enabled,
                    "preemph_limit_active": preemph_limit_active,
                    "composite_clip_enabled": composite_clip_enabled,
                    "composite_clip_active": composite_clip_active,
                    "scope_left": scope_left,
                    "scope_right": scope_right,
                    "mpx_pre_gain": mpx_pre_gain,
                    "proc_frames": proc_frames,
                }
            )
            self._last_telemetry_enqueue = now

        self.phase = (self.phase + (frames / self.sample_rate)) % 1.0
        self.tone_phase = (self.tone_phase + (frames / self.sample_rate)) % 1.0
        self.pan_phase = (self.pan_phase + (frames / self.sample_rate)) % 1.0
        if mpx_state.get("output_enabled", True):
            outdata[:, 0] = mpx
            outdata[:, 1] = mpx
        else:
            outdata.fill(0.0)

    def callback_output(self, outdata, frames, _time_info, _status):
        self._log_stream_status(_status, "output")
        self._process_frame(outdata, frames, None)

    def callback_duplex(self, indata, outdata, frames, _time_info, _status):
        self._log_stream_status(_status, "duplex")
        self._process_frame(outdata, frames, indata)
