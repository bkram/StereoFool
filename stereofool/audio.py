import math
import queue
import threading
import logging
import time
from collections import Counter

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

    def read_frames(self, frames):
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
            chunk += b"\x00" * (needed - len(chunk))
        data = np.frombuffer(chunk, dtype=self.dtype).reshape(frames, 2).copy()
        return data

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
        self.lookahead_buffer = None
        self.lookahead_samples = 0
        self.lookahead_gain = 1.0
        self.lookahead_buffer = None
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
                    meter_state["input_rms"] = meter_state["input_rms"] * 0.9 + input_rms * 0.1
                    meter_state["input_rms_l"] = meter_state["input_rms_l"] * 0.9 + left_rms * 0.1
                    meter_state["input_rms_r"] = meter_state["input_rms_r"] * 0.9 + right_rms * 0.1
                    meter_state["mpx_rms"] = meter_state["mpx_rms"] * 0.9 + mpx_rms * 0.1
                    meter_state["input_peak"] = max(meter_state["input_peak"] * 0.98, input_peak)
                    meter_state["mpx_peak"] = max(meter_state["mpx_peak"] * 0.98, mpx_peak)
                    meter_state["input_vu"] = meter_state["input_vu"] * 0.95 + input_rms * 0.05
                    meter_state["input_vu_l"] = meter_state["input_vu_l"] * 0.95 + left_vu * 0.05
                    meter_state["input_vu_r"] = meter_state["input_vu_r"] * 0.95 + right_vu * 0.05
                    meter_state["mpx_vu"] = meter_state["mpx_vu"] * 0.95 + mpx_rms * 0.05
                    meter_state["input_pre_rms"] = (
                        meter_state["input_pre_rms"] * 0.9 + input_pre_rms * 0.1
                    )
                    meter_state["input_pre_peak"] = max(
                        meter_state["input_pre_peak"] * 0.98, input_pre_peak
                    )
                    meter_state["input_pre_vu"] = (
                        meter_state["input_pre_vu"] * 0.95 + input_pre_rms * 0.05
                    )
                    meter_state["output_rms"] = meter_state["output_rms"] * 0.9 + output_rms * 0.1
                    meter_state["output_peak"] = max(meter_state["output_peak"] * 0.98, output_peak)
                    meter_state["output_vu"] = meter_state["output_vu"] * 0.95 + output_rms * 0.05
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
        self.pre_zi_sum = (dsp_signal.lfilter_zi(self.pre_b, self.pre_a) * 0).astype(self.dtype)
        self.pre_zi_diff = (dsp_signal.lfilter_zi(self.pre_b, self.pre_a) * 0).astype(self.dtype)

    def _init_dynamics(self):
        self.mb_env_low = 0.0
        self.mb_env_mid = 0.0
        self.mb_env_high = 0.0
        self.wide_p = np.zeros(4099, dtype=self.dtype)
        self.wide_count = 0
        self._init_multiband_filters()

    def _init_multiband_filters(self):
        self.mb_low_hz = float(mpx_state.get("multiband_low_hz", 400.0))
        self.mb_high_hz = float(mpx_state.get("multiband_high_hz", 2000.0))
        low = min(self.mb_low_hz, (self.proc_rate / 2) - 100.0)
        high = min(self.mb_high_hz, (self.proc_rate / 2) - 100.0)
        if high <= low + 50.0:
            high = low + 50.0
        self.mb_lp1_sos = dsp_signal.butter(4, low, btype="low", fs=self.proc_rate, output="sos")
        self.mb_hp1_sos = dsp_signal.butter(4, low, btype="high", fs=self.proc_rate, output="sos")
        self.mb_lp2_sos = dsp_signal.butter(4, high, btype="low", fs=self.proc_rate, output="sos")
        self.mb_hp2_sos = dsp_signal.butter(4, high, btype="high", fs=self.proc_rate, output="sos")
        self.mb_lp1_zi_l = (dsp_signal.sosfilt_zi(self.mb_lp1_sos) * 0).astype(self.dtype)
        self.mb_lp1_zi_r = (dsp_signal.sosfilt_zi(self.mb_lp1_sos) * 0).astype(self.dtype)
        self.mb_hp1_zi_l = (dsp_signal.sosfilt_zi(self.mb_hp1_sos) * 0).astype(self.dtype)
        self.mb_hp1_zi_r = (dsp_signal.sosfilt_zi(self.mb_hp1_sos) * 0).astype(self.dtype)
        self.mb_lp2_zi_l = (dsp_signal.sosfilt_zi(self.mb_lp2_sos) * 0).astype(self.dtype)
        self.mb_lp2_zi_r = (dsp_signal.sosfilt_zi(self.mb_lp2_sos) * 0).astype(self.dtype)
        self.mb_hp2_zi_l = (dsp_signal.sosfilt_zi(self.mb_hp2_sos) * 0).astype(self.dtype)
        self.mb_hp2_zi_r = (dsp_signal.sosfilt_zi(self.mb_hp2_sos) * 0).astype(self.dtype)
        self.mb_ap2_b, self.mb_ap2_a = self._allpass_coeffs(high, 0.707, self.proc_rate)
        self.mb_ap2_zi_l = (dsp_signal.lfilter_zi(self.mb_ap2_b, self.mb_ap2_a) * 0).astype(
            self.dtype
        )
        self.mb_ap2_zi_r = (dsp_signal.lfilter_zi(self.mb_ap2_b, self.mb_ap2_a) * 0).astype(
            self.dtype
        )

    def _allpass_coeffs(self, freq_hz, q, sample_rate):
        w0 = 2 * math.pi * float(freq_hz) / float(sample_rate)
        alpha = math.sin(w0) / (2.0 * q)
        cos_w0 = math.cos(w0)
        b0 = 1.0 - alpha
        b1 = -2.0 * cos_w0
        b2 = 1.0 + alpha
        a0 = 1.0 + alpha
        a1 = -2.0 * cos_w0
        a2 = 1.0 - alpha
        b = np.array([b0 / a0, b1 / a0, b2 / a0], dtype=self.dtype)
        a = np.array([1.0, a1 / a0, a2 / a0], dtype=self.dtype)
        return b, a

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
            self.de_b, self.de_a = dsp_signal.bilinear([1.0], [tau, 1.0], fs=self.sample_rate)
        else:
            self.de_b, self.de_a = np.array([1.0]), np.array([1.0])
        self.de_zi_l = (dsp_signal.lfilter_zi(self.de_b, self.de_a) * 0).astype(self.dtype)
        self.de_zi_r = (dsp_signal.lfilter_zi(self.de_b, self.de_a) * 0).astype(self.dtype)

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

    def _refresh_preemphasis(self):
        try:
            current = int(mpx_state.get("preemphasis_us", 0))
        except (TypeError, ValueError):
            current = 0
        if current != self.preemphasis_us:
            self.preemphasis_us = current
            self.pre_b, self.pre_a = self._preemphasis_coeffs(self.preemphasis_us, self.proc_rate)
            self.pre_zi_sum = (dsp_signal.lfilter_zi(self.pre_b, self.pre_a) * 0).astype(self.dtype)
            self.pre_zi_diff = (dsp_signal.lfilter_zi(self.pre_b, self.pre_a) * 0).astype(
                self.dtype
            )

    def _apply_preemphasis(self, baseband, diff):
        baseband, self.pre_zi_sum = dsp_signal.lfilter(
            self.pre_b, self.pre_a, baseband, zi=self.pre_zi_sum
        )
        diff, self.pre_zi_diff = dsp_signal.lfilter(
            self.pre_b, self.pre_a, diff, zi=self.pre_zi_diff
        )
        return baseband, diff

    def _apply_preemphasis_limiter(self, signal, threshold):
        return self._oversampled_soft_clip(signal, threshold, "_preemph_pad")

    def _apply_composite_clipper(self, mpx, threshold):
        return self._oversampled_soft_clip(mpx, threshold, "_composite_pad")

    def _oversampled_soft_clip(self, signal, threshold, pad_attr, os_factor=2, pad_len=96):
        if threshold <= 0 or not signal.size:
            return signal
        if os_factor <= 1:
            return (threshold * np.tanh(signal / threshold)).astype(self.dtype, copy=False)
        pad = getattr(self, pad_attr, None)
        if pad is None or pad.shape[0] != pad_len:
            pad = np.zeros(pad_len, dtype=self.dtype)
        combined = np.concatenate((pad, signal))
        target_len = combined.shape[0]
        oversampled = dsp_signal.resample_poly(combined, os_factor, 1)
        oversampled = threshold * np.tanh(oversampled / threshold)
        resampled = dsp_signal.resample_poly(oversampled, 1, os_factor)
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
        mpx, self.audio_mpx_lpf_zi = dsp_signal.sosfilt(
            self.audio_mpx_lpf_sos, mpx, zi=self.audio_mpx_lpf_zi
        )
        return mpx

    def _juce_compressor(self, left, right, threshold_db, ratio, attack_ms, release_ms, env_state):
        if not left.size:
            return left, right, env_state
        if ratio <= 1.0:
            return left, right, env_state
        attack_ms = max(0.0, float(attack_ms))
        release_ms = max(0.0, float(release_ms))
        if attack_ms <= 0.0:
            attack_coeff = 0.0
        else:
            attack_coeff = math.exp(-1.0 / (self.proc_rate * (attack_ms / 1000.0)))
        if release_ms <= 0.0:
            release_coeff = 0.0
        else:
            release_coeff = math.exp(-1.0 / (self.proc_rate * (release_ms / 1000.0)))
        level = np.sqrt((left * left + right * right) * 0.5)
        env = np.empty_like(level)
        e = float(env_state)
        for i, x in enumerate(level):
            if x > e:
                e = (attack_coeff * e) + ((1.0 - attack_coeff) * x)
            else:
                e = (release_coeff * e) + ((1.0 - release_coeff) * x)
            env[i] = e
        env_db = 20.0 * np.log10(np.maximum(env, 1e-9))
        over_db = env_db - threshold_db
        gain_db = np.where(over_db > 0.0, -(over_db - (over_db / ratio)), 0.0)
        gain = np.power(10.0, gain_db / 20.0).astype(self.dtype, copy=False)
        left = left * gain
        right = right * gain
        return left, right, float(e)

    def _apply_widener(self, left, right):
        if not bool(mpx_state.get("stereo_widen_enabled")):
            return left, right
        width = float(mpx_state.get("stereo_widen_width", 0.5))
        center = float(mpx_state.get("stereo_widen_center", 0.5))
        mix = float(mpx_state.get("stereo_widen_mix", 1.0))
        width = max(0.0, min(1.0, width))
        center = max(0.0, min(1.0, center))
        mix = max(0.0, min(1.0, mix))
        density_side = (width * 2.0) - 1.0
        density_mid = (center * 2.0) - 1.0
        wet = mix * 0.5
        level_comp = 1.0 / (1.0 + wet) if wet > 0.0 else 1.0
        offset = (density_side - density_mid) / 2.0
        if offset > 0:
            offset = math.sin(offset)
        elif offset < 0:
            offset = -math.sin(-offset)
        overallscale = float(self.sample_rate) / 44100.0
        offset = -(offset**4) * 20.0 * overallscale
        near = int(math.floor(abs(offset)))
        far_level = abs(offset) - near
        far = near + 1
        near_level = 1.0 - far_level
        count = self.wide_count
        p = self.wide_p
        out_l = np.empty_like(left)
        out_r = np.empty_like(right)
        for i in range(left.shape[0]):
            input_l = float(left[i])
            input_r = float(right[i])
            dry_l = input_l
            dry_r = input_r
            mid = input_l + input_r
            side = input_l - input_r
            if density_side != 0.0:
                out = abs(density_side)
                bridgerectifier = abs(side) * 1.57079633
                if bridgerectifier > 1.57079633:
                    bridgerectifier = 1.57079633
                if density_side > 0:
                    bridgerectifier = math.sin(bridgerectifier)
                else:
                    bridgerectifier = 1.0 - math.cos(bridgerectifier)
                if side > 0:
                    side = (side * (1.0 - out)) + (bridgerectifier * out)
                else:
                    side = (side * (1.0 - out)) - (bridgerectifier * out)
            if density_mid != 0.0:
                out = abs(density_mid)
                bridgerectifier = abs(mid) * 1.57079633
                if bridgerectifier > 1.57079633:
                    bridgerectifier = 1.57079633
                if density_mid > 0:
                    bridgerectifier = math.sin(bridgerectifier)
                else:
                    bridgerectifier = 1.0 - math.cos(bridgerectifier)
                if mid > 0:
                    mid = (mid * (1.0 - out)) + (bridgerectifier * out)
                else:
                    mid = (mid * (1.0 - out)) - (bridgerectifier * out)
            if count < 1 or count > 2048:
                count = 2048
            if offset > 0.0:
                p[count + 2048] = p[count] = mid
                mid = (p[count + near] * near_level) + (p[count + far] * far_level)
            elif offset < 0.0:
                p[count + 2048] = p[count] = side
                side = (p[count + near] * near_level) + (p[count + far] * far_level)
            count -= 1
            out_l[i] = ((dry_l * (1.0 - wet)) + ((mid + side) * wet)) * level_comp
            out_r[i] = ((dry_r * (1.0 - wet)) + ((mid - side) * wet)) * level_comp
        self.wide_count = count
        return out_l.astype(self.dtype, copy=False), out_r.astype(self.dtype, copy=False)

    def _apply_multiband(self, left, right, frames):
        if not bool(mpx_state.get("multiband_enabled")):
            return left, right
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
        low_l, self.mb_lp1_zi_l = dsp_signal.sosfilt(self.mb_lp1_sos, left, zi=self.mb_lp1_zi_l)
        low_r, self.mb_lp1_zi_r = dsp_signal.sosfilt(self.mb_lp1_sos, right, zi=self.mb_lp1_zi_r)
        low_l, self.mb_ap2_zi_l = dsp_signal.lfilter(
            self.mb_ap2_b, self.mb_ap2_a, low_l, zi=self.mb_ap2_zi_l
        )
        low_r, self.mb_ap2_zi_r = dsp_signal.lfilter(
            self.mb_ap2_b, self.mb_ap2_a, low_r, zi=self.mb_ap2_zi_r
        )
        mid_l, self.mb_hp1_zi_l = dsp_signal.sosfilt(self.mb_hp1_sos, left, zi=self.mb_hp1_zi_l)
        mid_r, self.mb_hp1_zi_r = dsp_signal.sosfilt(self.mb_hp1_sos, right, zi=self.mb_hp1_zi_r)
        mid_l, self.mb_lp2_zi_l = dsp_signal.sosfilt(self.mb_lp2_sos, mid_l, zi=self.mb_lp2_zi_l)
        mid_r, self.mb_lp2_zi_r = dsp_signal.sosfilt(self.mb_lp2_sos, mid_r, zi=self.mb_lp2_zi_r)
        high_l, self.mb_hp2_zi_l = dsp_signal.sosfilt(self.mb_hp2_sos, left, zi=self.mb_hp2_zi_l)
        high_r, self.mb_hp2_zi_r = dsp_signal.sosfilt(self.mb_hp2_sos, right, zi=self.mb_hp2_zi_r)
        low_l, low_r, self.mb_env_low = self._juce_compressor(
            low_l, low_r, threshold_low, ratio_low, attack_low, release_low, self.mb_env_low
        )
        mid_l, mid_r, self.mb_env_mid = self._juce_compressor(
            mid_l, mid_r, threshold_mid, ratio_mid, attack_mid, release_mid, self.mb_env_mid
        )
        high_l, high_r, self.mb_env_high = self._juce_compressor(
            high_l, high_r, threshold_high, ratio_high, attack_high, release_high, self.mb_env_high
        )
        out_l = low_l + mid_l + high_l
        out_r = low_r + mid_r + high_r
        return out_l, out_r

    def _resample(self, data, up, down, target_len):
        if up == down or not data.size:
            return data
        resampled = dsp_signal.resample_poly(data, up, down, axis=0)
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
        gain = float(np.min(margin[mask] / abs_audio[mask]))
        gain = max(0.0, min(1.0, gain))
        return audio * gain, gain

    def _reset_dsp_state(self):
        self.mb_env_low = 0.0
        self.mb_env_mid = 0.0
        self.mb_env_high = 0.0
        self.wide_p = np.zeros(4099, dtype=self.dtype)
        self.wide_count = 0
        self.lookahead_buffer = None
        self.lookahead_gain = 1.0
        self.lookahead_samples = 0
        for name in ("_preemph_pad", "_composite_pad"):
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
            "mb_ap2_zi_l",
            "mb_ap2_zi_r",
            "bpf_zi",
            "audio_mpx_lpf_zi",
            "mpx_dc_zi",
            "mpx_notch_zi",
            "mon_lpf_zi",
            "mon_lpf_zi_diff",
            "mon_bpf_zi",
            "de_zi_l",
            "de_zi_r",
        )
        for name in zi_names:
            if hasattr(self, name):
                state = getattr(self, name)
                try:
                    setattr(self, name, np.zeros_like(state))
                except Exception:
                    continue

    def _apply_lookahead_limiter(self, mpx, threshold):
        if threshold <= 0:
            return mpx, False
        enabled = bool(mpx_state.get("limit_lookahead_enabled", True))
        if not enabled:
            return mpx, False
        try:
            la_ms = float(mpx_state.get("limit_lookahead_ms", 5.0))
        except (TypeError, ValueError):
            la_ms = 5.0
        la_ms = max(0.0, min(20.0, la_ms))
        la_samples = max(1, int(self.sample_rate * la_ms / 1000.0))
        if self.lookahead_buffer is None or la_samples != self.lookahead_samples:
            self.lookahead_samples = la_samples
            self.lookahead_buffer = np.zeros(la_samples, dtype=self.dtype)
            self.lookahead_gain = 1.0
        buf = self.lookahead_buffer
        combined = np.concatenate((buf, mpx))
        # Lookahead peak across the buffer window.
        window_peak = float(np.max(np.abs(combined))) if combined.size else 0.0
        target_gain = min(1.0, threshold / window_peak) if window_peak > 1e-6 else 1.0
        # Smooth changes to avoid pumping.
        attack_ms = 2.0
        release_ms = 60.0
        frames = mpx.shape[0]
        self.lookahead_gain = self._smooth_gain(
            self.lookahead_gain, target_gain, frames, attack_ms, release_ms
        )
        limited = mpx * self.lookahead_gain
        self.lookahead_buffer = combined[frames : frames + la_samples].copy()
        return limited, target_gain < 0.999

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
                if not bypass:
                    self._refresh_hpf()
                    self._refresh_hf_trim()
                    left, right = self._apply_hpf(left, right)
                    left, right = self._apply_lpf(left, right)
                    left, right = self._apply_hf_trim(left, right)
                    left, right = self._apply_pilot_notch(left, right)
                    left, right = self._apply_multiband(left, right, proc_frames)
                    left, right = self._apply_widener(left, right)
                else:
                    left, right = self._apply_lpf(left, right)
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
                    stereo = self.audio_in.read_frames(frames)
                    input_pre_rms = float(np.sqrt(np.mean(stereo**2))) if stereo.size else 0.0
                    input_pre_peak = float(np.max(np.abs(stereo))) if stereo.size else 0.0
                    if input_gain != 1.0:
                        stereo = stereo * input_gain
                    if proc_rate != self.sample_rate:
                        stereo = self._resample(stereo, up, down, proc_frames)
                    left = stereo[:, 0]
                    right = stereo[:, 1]
                    if not bypass:
                        self._refresh_hpf()
                        self._refresh_hf_trim()
                        left, right = self._apply_hpf(left, right)
                        left, right = self._apply_lpf(left, right)
                        left, right = self._apply_hf_trim(left, right)
                        left, right = self._apply_pilot_notch(left, right)
                        left, right = self._apply_multiband(left, right, proc_frames)
                        left, right = self._apply_widener(left, right)
                    else:
                        left, right = self._apply_lpf(left, right)
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
            if not bypass:
                self._refresh_hpf()
                self._refresh_hf_trim()
                left, right = self._apply_hpf(left, right)
                left, right = self._apply_lpf(left, right)
                left, right = self._apply_hf_trim(left, right)
                left, right = self._apply_pilot_notch(left, right)
                left, right = self._apply_multiband(left, right, proc_frames)
                left, right = self._apply_widener(left, right)
            else:
                left, right = self._apply_lpf(left, right)
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
        self._refresh_preemphasis()
        if self.preemphasis_us:
            baseband, diff = self._apply_preemphasis(baseband, diff)
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
            baseband = self._apply_preemphasis_limiter(baseband, threshold)
            diff = self._apply_preemphasis_limiter(diff, threshold)
        if not bypass:
            max_audio = 0.0
            if baseband.size:
                max_audio = max(max_audio, float(np.max(np.abs(baseband))))
            if diff.size:
                max_audio = max(max_audio, float(np.max(np.abs(diff))))
            if max_audio > 0.9:
                gain = 0.9 / max_audio
                baseband = baseband * gain
                diff = diff * gain
        if proc_rate != self.sample_rate:
            baseband = self._resample(baseband, down, up, frames)
            diff = self._resample(diff, down, up, frames)
        subcarrier = np.sin(2 * np.pi * (2 * PILOT_FREQ) * t)
        dsb_sc = diff * subcarrier
        dsb_sc, self.bpf_zi = dsp_signal.sosfilt(self.bpf_sos, dsb_sc, zi=self.bpf_zi)

        mpx_audio = baseband + dsb_sc
        if not bypass:
            mpx_audio = self._apply_audio_mpx_lpf(mpx_audio)

        en_rds = bool(mpx_state.get("en_rds"))
        if en_rds and not self.rds_enabled:
            # Reset RDS generator when re-enabled for a clean restart.
            self.rds = RDSSubcarrier(self.sample_rate)
        self.rds_enabled = en_rds

        composite_clip_enabled = bool(mpx_state.get("composite_clip_enabled")) and not bypass
        composite_clip_active = False
        if composite_clip_enabled:
            comp_threshold = float(mpx_state.get("composite_clip_threshold", 0.98))
            pre_clip_peak = float(np.max(np.abs(mpx_audio))) if mpx_audio.size else 0.0
            composite_clip_active = pre_clip_peak > comp_threshold
            mpx_audio = self._apply_composite_clipper(mpx_audio, comp_threshold)

        pre_limit_peak = float(np.max(np.abs(mpx_audio))) if mpx_audio.size else 0.0
        la_active = False
        if mpx_state.get("limit_mpx") and not bypass:
            threshold = float(mpx_state.get("limit_threshold", 0.98))
            if threshold > 0:
                mpx_audio, la_active = self._apply_lookahead_limiter(mpx_audio, threshold)
                # 2x oversample for cleaner limiter behavior at the MPX stage.
                os_mpx = dsp_signal.resample_poly(mpx_audio, 2, 1)
                os_mpx = threshold * np.tanh(os_mpx / threshold)
                mpx_audio = dsp_signal.resample_poly(os_mpx, 1, 2)
                if mpx_audio.size > frames:
                    mpx_audio = mpx_audio[:frames]
                elif mpx_audio.size < frames:
                    mpx_audio = np.pad(mpx_audio, (0, frames - mpx_audio.size))

        mpx_audio = mpx_audio * (float(mpx_state.get("mpx_deviation_khz", 75.0)) / 75.0)

        pilot_sig = np.zeros_like(mpx_audio)
        if not mono_mode:
            pilot_sig = pilot

        rds_sig = np.zeros_like(mpx_audio)
        if en_rds:
            rds_sig = self.rds.synthesize(frames, self.phase).astype(self.dtype, copy=False)
        carriers = pilot_sig + rds_sig

        limit_enabled = bool(mpx_state.get("limit_mpx")) and not bypass
        threshold = float(mpx_state.get("limit_threshold", 0.98)) if limit_enabled else 1.0
        audio_gain = 1.0
        if threshold > 0 and not bypass:
            mpx_audio, audio_gain = self._apply_audio_headroom(mpx_audio, carriers, threshold)

        mpx = mpx_audio + carriers
        if not bypass:
            self._refresh_mpx_cleanup()
            mpx = self._apply_mpx_dc_block(mpx)
            mpx = self._apply_mpx_notch(mpx)
        limiter_active = bool(
            limit_enabled
            and (
                pre_limit_peak > float(mpx_state.get("limit_threshold", 0.98))
                or la_active
                or audio_gain < 0.999
            )
        )
        mpx_rms = float(np.sqrt(np.mean(mpx**2))) if mpx.size else 0.0
        mpx_peak = float(np.max(np.abs(mpx))) if mpx.size else 0.0
        output_gain_db = float(mpx_state.get("output_gain_db", 0.0))
        mpx_pre_gain = mpx
        if output_gain_db:
            mpx = mpx * (10 ** (output_gain_db / 20.0))
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
