import ctypes
import logging
import os
import queue
import sys
import threading
import time
import wave
from collections import deque
from typing import Any, Mapping, Sequence, cast

import numpy as np
import sounddevice as sd
from scipy import signal as dsp_signal

from stereofool.audio import FMEngine
from stereofool.constants import BLOCKSIZE, DEFAULT_SAMPLE_RATE, FALLBACK_SAMPLE_RATE
from stereofool.rds import parse_text_source
from stereofool.state import (
    dsp_control,
    meter_lock,
    meter_state,
    monitor_data,
    monitor_lock,
    mpx_state,
    rds_state,
    resolved_cache,
    wave_lock,
    wave_state,
)

logger = logging.getLogger("stereofool.audio_worker")
TELEMETRY_INTERVAL_SECONDS = 0.1
CONTROL_APPLY_INTERVAL_SECONDS = 0.05

audio_thread_lock = threading.Lock()
audio_thread: threading.Thread | None = None
restart_lock = threading.Lock()
restart_state = {"pending": False}
shutdown_event = threading.Event()
capture_complete_event = threading.Event()
state_update_lock = threading.Lock()
pending_mpx_updates: dict[str, Any] = {}
pending_rds_updates: dict[str, Any] = {}
pending_dsp_reset = False


def _coerce_bool(val: Any) -> bool:
    if isinstance(val, str):
        return val.strip().lower() in {"true", "1", "yes", "on"}
    return bool(val)


def _normalize_audio_priority_profile(value: Any) -> str:
    token = str(value or "normal").strip().lower()
    alias_map = {
        "normal": "normal",
        "high": "high",
        "realtime": "realtime-attempt",
        "rt": "realtime-attempt",
        "realtime-attempt": "realtime-attempt",
    }
    return alias_map.get(token, "normal")


def _set_process_nice(target_nice: int) -> tuple[bool, str]:
    if not hasattr(os, "setpriority") or not hasattr(os, "PRIO_PROCESS"):
        return False, "setpriority unsupported"
    try:
        os.setpriority(os.PRIO_PROCESS, 0, int(target_nice))
        return True, ""
    except PermissionError:
        return False, "permission denied"
    except Exception as exc:
        return False, str(exc)


def _set_macos_thread_qos(profile: str) -> tuple[bool, str]:
    if sys.platform != "darwin":
        return False, "not macos"
    qos_map = {
        "high": 0x19,  # QOS_CLASS_USER_INITIATED
        "realtime-attempt": 0x21,  # QOS_CLASS_USER_INTERACTIVE
    }
    qos_class = qos_map.get(profile)
    if qos_class is None:
        return True, ""
    try:
        libc = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
        set_qos = getattr(libc, "pthread_set_qos_class_self_np", None)
        if set_qos is None:
            return False, "pthread_set_qos_class_self_np unavailable"
        set_qos.argtypes = [ctypes.c_uint, ctypes.c_int]
        set_qos.restype = ctypes.c_int
        rc = int(set_qos(ctypes.c_uint(qos_class), ctypes.c_int(0)))
        if rc == 0:
            return True, ""
        return False, f"pthread_set_qos_class_self_np rc={rc}"
    except Exception as exc:
        return False, str(exc)


def _set_windows_process_priority(profile: str) -> tuple[bool, str]:
    if not sys.platform.startswith("win"):
        return False, "not windows"
    class_map = {
        "normal": 0x00000020,  # NORMAL_PRIORITY_CLASS
        "high": 0x00000080,  # HIGH_PRIORITY_CLASS
        "realtime-attempt": 0x00000080,  # keep safe; MMCSS handles RT intent
    }
    prio_class = class_map.get(profile, 0x00000020)
    try:
        win_dll = getattr(ctypes, "WinDLL", None)
        get_last_error = getattr(ctypes, "get_last_error", None)
        if win_dll is None or get_last_error is None:
            return False, "WinDLL/get_last_error unavailable"
        kernel32 = win_dll("kernel32", use_last_error=True)
        get_current_process = getattr(kernel32, "GetCurrentProcess")
        set_priority_class = getattr(kernel32, "SetPriorityClass")
        get_current_process.restype = ctypes.c_void_p
        set_priority_class.argtypes = [ctypes.c_void_p, ctypes.c_uint]
        set_priority_class.restype = ctypes.c_int
        proc = get_current_process()
        ok = int(set_priority_class(proc, ctypes.c_uint(prio_class)))
        if ok:
            return True, ""
        return False, f"SetPriorityClass error={int(get_last_error())}"
    except Exception as exc:
        return False, str(exc)


def _set_windows_thread_priority(profile: str) -> tuple[bool, str]:
    if not sys.platform.startswith("win"):
        return False, "not windows"
    priority_map = {
        "normal": 0,  # THREAD_PRIORITY_NORMAL
        "high": 2,  # THREAD_PRIORITY_HIGHEST
        "realtime-attempt": 2,  # keep safe; MMCSS handles RT intent
    }
    thread_prio = priority_map.get(profile, 0)
    try:
        win_dll = getattr(ctypes, "WinDLL", None)
        get_last_error = getattr(ctypes, "get_last_error", None)
        if win_dll is None or get_last_error is None:
            return False, "WinDLL/get_last_error unavailable"
        kernel32 = win_dll("kernel32", use_last_error=True)
        get_current_thread = getattr(kernel32, "GetCurrentThread")
        set_thread_priority = getattr(kernel32, "SetThreadPriority")
        get_current_thread.restype = ctypes.c_void_p
        set_thread_priority.argtypes = [ctypes.c_void_p, ctypes.c_int]
        set_thread_priority.restype = ctypes.c_int
        thread = get_current_thread()
        ok = int(set_thread_priority(thread, ctypes.c_int(thread_prio)))
        if ok:
            return True, ""
        return False, f"SetThreadPriority error={int(get_last_error())}"
    except Exception as exc:
        return False, str(exc)


def _set_windows_mmcss_if_requested(profile: str) -> tuple[bool, str]:
    if not sys.platform.startswith("win"):
        return False, "not windows"
    if profile != "realtime-attempt":
        return True, ""
    try:
        win_dll = getattr(ctypes, "WinDLL", None)
        get_last_error = getattr(ctypes, "get_last_error", None)
        if win_dll is None or get_last_error is None:
            return False, "WinDLL/get_last_error unavailable"
        avrt = win_dll("Avrt.dll", use_last_error=True)
    except Exception:
        return False, "Avrt.dll unavailable"
    try:
        task_index = ctypes.c_uint(0)
        av_set = getattr(avrt, "AvSetMmThreadCharacteristicsW")
        av_set.argtypes = [ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_uint)]
        av_set.restype = ctypes.c_void_p
        handle = av_set("Pro Audio", ctypes.byref(task_index))
        if handle:
            return True, ""
        return False, f"AvSetMmThreadCharacteristicsW error={int(get_last_error())}"
    except Exception as exc:
        return False, str(exc)


def _apply_audio_priority_profile(context: str) -> None:
    profile = _normalize_audio_priority_profile(mpx_state.get("audio_priority_profile", "normal"))
    if sys.platform == "darwin":
        target_nice = {"normal": 0, "high": -5, "realtime-attempt": -10}[profile]
        nice_ok, nice_err = _set_process_nice(target_nice)
        qos_ok, qos_err = _set_macos_thread_qos(profile)
        if nice_ok and qos_ok:
            logger.info("StereoFool: macOS audio priority '%s' applied (%s)", profile, context)
            return
        if profile == "normal":
            logger.info("StereoFool: macOS audio priority reset to normal (%s)", context)
            return
        logger.warning(
            "StereoFool: macOS audio priority '%s' partial/failed (%s): nice=%s qos=%s",
            profile,
            context,
            "ok" if nice_ok else nice_err,
            "ok" if qos_ok else qos_err,
        )
        return
    if sys.platform.startswith("win"):
        proc_ok, proc_err = _set_windows_process_priority(profile)
        thread_ok, thread_err = _set_windows_thread_priority(profile)
        mmcss_ok, mmcss_err = _set_windows_mmcss_if_requested(profile)
        if proc_ok and thread_ok and mmcss_ok:
            logger.info("StereoFool: Windows audio priority '%s' applied (%s)", profile, context)
            return
        if profile == "normal":
            logger.info("StereoFool: Windows audio priority reset to normal (%s)", context)
            return
        logger.warning(
            "StereoFool: Windows audio priority '%s' partial/failed (%s): proc=%s thread=%s mmcss=%s",
            profile,
            context,
            "ok" if proc_ok else proc_err,
            "ok" if thread_ok else thread_err,
            "ok" if mmcss_ok else mmcss_err,
        )
        return
    if profile != "normal":
        logger.info(
            "StereoFool: audio priority profile '%s' requested (%s), unsupported on %s",
            profile,
            context,
            sys.platform,
        )


def _coerce_state_value(current: Any, new_value: Any) -> Any:
    if isinstance(current, bool):
        return _coerce_bool(new_value)
    if isinstance(current, int) and not isinstance(current, bool):
        return int(new_value)
    if isinstance(current, float):
        return float(new_value)
    return new_value


def _apply_state_update(target: dict[str, Any], updates: Mapping[str, Any]) -> None:
    coerced: dict[str, Any] = {}
    for key, value in updates.items():
        if key not in target:
            continue
        try:
            coerced[key] = _coerce_state_value(target[key], value)
        except Exception:
            continue
    if coerced:
        target.update(coerced)


def _queue_state_update(mpx_updates: Mapping[str, Any], rds_updates: Mapping[str, Any]) -> None:
    with state_update_lock:
        pending_mpx_updates.update(mpx_updates)
        pending_rds_updates.update(rds_updates)


def _queue_dsp_reset() -> None:
    global pending_dsp_reset
    with state_update_lock:
        pending_dsp_reset = True


def _flush_pending_updates() -> bool:
    global pending_dsp_reset
    with state_update_lock:
        if not pending_mpx_updates and not pending_rds_updates and not pending_dsp_reset:
            return False
        mpx_updates = dict(pending_mpx_updates)
        rds_updates = dict(pending_rds_updates)
        do_reset = pending_dsp_reset
        pending_mpx_updates.clear()
        pending_rds_updates.clear()
        pending_dsp_reset = False
    if mpx_updates:
        _apply_state_update(mpx_state, mpx_updates)
    if rds_updates:
        _apply_state_update(rds_state, rds_updates)
    if do_reset:
        dsp_control["reset"] = True
    return True


def resolve_blocksize() -> int:
    raw = mpx_state.get("blocksize", BLOCKSIZE)
    try:
        value = int(raw)
    except (TypeError, ValueError):
        value = BLOCKSIZE
    if value < 256:
        return 256
    if value > 262144:
        return 262144
    return value


def select_sample_rate(device_out_idx: int, device_in_idx: int | None) -> int:
    for rate in (DEFAULT_SAMPLE_RATE, FALLBACK_SAMPLE_RATE):
        try:
            sd.check_output_settings(device=device_out_idx, samplerate=rate)
            if device_in_idx is not None and device_in_idx >= 0:
                sd.check_input_settings(device=device_in_idx, samplerate=rate)
            return rate
        except Exception:
            continue
    return FALLBACK_SAMPLE_RATE


class WavCapture:
    def __init__(self, path: str, source_rate: int, target_rate: int = DEFAULT_SAMPLE_RATE):
        self.path = path
        self.source_rate = int(source_rate)
        self.target_rate = int(target_rate)
        self.queue: queue.Queue[np.ndarray] = queue.Queue(maxsize=12)
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._writer_loop, daemon=True)
        self.dropped = 0

    def start(self) -> None:
        self.thread.start()

    def push(self, data: np.ndarray) -> None:
        if self.stop_event.is_set():
            return
        try:
            chunk = np.asarray(data, dtype=np.float32)
            self.queue.put_nowait(chunk.copy())
        except queue.Full:
            self.dropped += 1

    def stop(self, timeout: float = 1.0) -> None:
        self.stop_event.set()
        self.thread.join(timeout=timeout)
        if self.dropped:
            logger.info("StereoFool: WAV capture dropped %s blocks", self.dropped)

    def _writer_loop(self) -> None:
        try:
            with wave.open(self.path, "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(self.target_rate)
                while not self.stop_event.is_set() or not self.queue.empty():
                    try:
                        chunk = self.queue.get(timeout=0.2)
                    except queue.Empty:
                        continue
                    if self.source_rate != self.target_rate:
                        chunk = dsp_signal.resample_poly(chunk, self.target_rate, self.source_rate)
                    chunk = np.clip(chunk, -1.0, 1.0)
                    pcm = (chunk * 32767.0).astype(np.int16)
                    wav.writeframes(pcm.tobytes())
        except Exception as exc:
            logger.warning("StereoFool: WAV capture error: %s", exc)


class MonitorOutput:
    def __init__(self, device_idx: int, sample_rate: int, blocksize: int = BLOCKSIZE):
        self.device_idx = device_idx
        self.sample_rate = int(sample_rate)
        self.blocksize = max(1, int(blocksize))
        self._last_status_log = 0.0
        self._last_status_summary_log = 0.0
        self._status_counts: dict[str, int] = {}
        self.prefill_frames = max(self.blocksize * 3, 2048)
        self.max_buffer_frames = max(self.blocksize * 16, self.prefill_frames * 2)
        self.buffered_frames = 0
        self.buffer_lock = threading.Lock()
        self.chunks: deque[np.ndarray] = deque()
        self.chunk_offset = 0
        self.stream: sd.OutputStream | None = None
        self.waiting_prefill = True
        self.queue_drop_frames = 0
        self.queue_underruns = 0

    def start(self) -> None:
        if self.device_idx is None or self.device_idx < 0:
            return
        self.stream = sd.OutputStream(
            device=self.device_idx,
            samplerate=self.sample_rate,
            blocksize=self.blocksize,
            channels=2,
            latency="high",
            callback=self._callback,
        )
        self.stream.start()

    def stop(self) -> None:
        if self.stream:
            try:
                self.stream.stop()
                self.stream.close()
            except Exception:
                pass
            self.stream = None
        if self._status_counts:
            logger.warning(
                "StereoFool: monitor stream status totals: %s",
                ", ".join(f"{k}={v}" for k, v in sorted(self._status_counts.items())),
            )
        if self.queue_drop_frames:
            logger.warning("StereoFool: monitor queue dropped %s frames", self.queue_drop_frames)
        if self.queue_underruns:
            logger.warning("StereoFool: monitor queue underruns %s", self.queue_underruns)

    def push(self, data: np.ndarray) -> None:
        if self.stream is None:
            return
        try:
            chunk = np.asarray(data, dtype=np.float32)
            if chunk.ndim == 1:
                chunk = np.column_stack((chunk, chunk))
            if chunk.shape[1] != 2:
                return
            with self.buffer_lock:
                self.chunks.append(chunk.copy())
                self.buffered_frames += chunk.shape[0]
                if self.buffered_frames > self.max_buffer_frames:
                    drop = self.buffered_frames - self.max_buffer_frames
                    dropped = 0
                    while self.chunks and drop > 0:
                        head = self.chunks[0]
                        remaining = head.shape[0] - self.chunk_offset
                        if drop < remaining:
                            self.chunk_offset += drop
                            self.buffered_frames -= drop
                            dropped += drop
                            drop = 0
                        else:
                            drop -= remaining
                            self.buffered_frames -= remaining
                            dropped += remaining
                            self.chunks.popleft()
                            self.chunk_offset = 0
                    if dropped > 0:
                        self.queue_drop_frames += dropped
                        self._status_counts["queue_drop"] = self._status_counts.get("queue_drop", 0) + 1
        except Exception:
            return

    def _callback(self, outdata: np.ndarray, frames: int, _time_info: Any, _status: Any) -> None:
        if _status:
            self._accumulate_status(_status)
            now = time.monotonic()
            if now - self._last_status_log >= 1.0:
                logger.warning("StereoFool: monitor stream status: %s", _status)
                self._last_status_log = now
            if now - self._last_status_summary_log >= 5.0 and self._status_counts:
                logger.warning(
                    "StereoFool: monitor stream status totals: %s",
                    ", ".join(f"{k}={v}" for k, v in sorted(self._status_counts.items())),
                )
                self._last_status_summary_log = now
        out = np.zeros((frames, 2), dtype=np.float32)
        with self.buffer_lock:
            if self.waiting_prefill and self.buffered_frames >= self.prefill_frames:
                self.waiting_prefill = False
        if self.waiting_prefill:
            outdata[:] = out
            return
        filled = 0
        with self.buffer_lock:
            while filled < frames and self.chunks:
                head = self.chunks[0]
                start = self.chunk_offset
                available = head.shape[0] - start
                take = min(available, frames - filled)
                out[filled : filled + take] = head[start : start + take]
                filled += take
                self.buffered_frames -= take
                if take < available:
                    self.chunk_offset += take
                else:
                    self.chunks.popleft()
                    self.chunk_offset = 0
        if filled < frames:
            self.queue_underruns += 1
            self._status_counts["queue_underrun"] = self._status_counts.get("queue_underrun", 0) + 1
            self.waiting_prefill = True
        outdata[:] = out

    def _accumulate_status(self, status: Any) -> None:
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
                    self._status_counts[key] = self._status_counts.get(key, 0) + 1
                    seen_flag = True
            except Exception:
                continue
        if not seen_flag:
            key = str(status)
            self._status_counts[key] = self._status_counts.get(key, 0) + 1


def run_audio(capture_seconds: float | None = None) -> bool:
    _apply_audio_priority_profile("audio thread")
    timed_out = False
    output_enabled = bool(mpx_state.get("output_enabled", True))
    sd_out = mpx_state["device_out_idx"]
    blocksize = resolve_blocksize()
    if output_enabled and sd_out is not None and sd_out >= 0:
        sample_rate = select_sample_rate(sd_out, mpx_state.get("device_in_idx", -1))
    else:
        output_enabled = False
        sample_rate = DEFAULT_SAMPLE_RATE
    if sample_rate != DEFAULT_SAMPLE_RATE:
        logger.warning("StereoFool: falling back to %s Hz", sample_rate)
        if sample_rate < 106000:
            logger.warning("StereoFool: stereo subcarrier band will be truncated at this sample rate")
    capture = None
    monitor = None
    if mpx_state.get("wav_record_enabled"):
        path = str(mpx_state.get("wav_record_path", "mpx_capture.wav")).strip()
        if path:
            capture = WavCapture(path, sample_rate, DEFAULT_SAMPLE_RATE)
            capture.start()
            logger.info("StereoFool: WAV capture enabled (%s, %s Hz)", path, DEFAULT_SAMPLE_RATE)
    if capture and capture_seconds:
        logger.info("StereoFool: WAV capture length %s seconds", capture_seconds)
    monitor_enabled = bool(mpx_state.get("monitor_enabled"))
    monitor_rate = int(mpx_state.get("monitor_rate_hz", 48000))
    monitor_device = int(mpx_state.get("monitor_device_idx", -1))
    if (
        monitor_enabled
        and monitor_device >= 0
        and output_enabled
        and sd_out is not None
        and sd_out >= 0
        and monitor_device == sd_out
    ):
        output_enabled = False
        logger.info("StereoFool: monitor device matches output device; disabling MPX output for monitor mode")
    monitor_blocksize = max(1, int(round(blocksize * (monitor_rate / float(sample_rate)))))
    if monitor_enabled and monitor_device >= 0:
        monitor = MonitorOutput(monitor_device, monitor_rate, blocksize=monitor_blocksize)
        monitor.start()
        logger.info("StereoFool: monitor output enabled (device=%s, rate=%s)", monitor_device, monitor_rate)
    engine = FMEngine(
        sample_rate,
        capture_callback=capture.push if capture else None,
        monitor_callback=monitor.push if monitor else None,
        monitor_rate=monitor_rate,
        blocksize=blocksize,
    )
    try:
        sd_out = mpx_state["device_out_idx"]
        sd_in = mpx_state.get("device_in_idx", -1)
        try:
            devs = cast(Sequence[Mapping[str, Any]], sd.query_devices())
            out_name = (
                str(devs[sd_out]["name"])
                if output_enabled and sd_out is not None and sd_out >= 0
                else "Disabled"
            )
            in_name = str(devs[sd_in]["name"]) if sd_in is not None and sd_in >= 0 else "None"
        except Exception:
            out_name = "Unknown"
            in_name = "Unknown"
        logger.info(
            "StereoFool: starting audio (out=%s:%s, in=%s:%s, rate=%s)",
            sd_out if output_enabled else "off",
            out_name,
            sd_in,
            in_name,
            sample_rate,
        )
        with monitor_lock:
            monitor_data["sample_rate"] = sample_rate
            monitor_data["device_out_name"] = out_name
            monitor_data["device_in_name"] = in_name
        if not output_enabled:
            start_time = time.time()
            if mpx_state.get("source_mode") == "input" and sd_in >= 0:
                last_status_log = [0.0]

                def _input_only_callback(indata: np.ndarray, frames: int, _time_info: Any, _status: Any) -> None:
                    if _status:
                        now = time.monotonic()
                        last = last_status_log[0]
                        if now - last >= 1.0:
                            logger.warning("StereoFool: input-only stream status: %s", _status)
                            last_status_log[0] = now
                    outdata = np.zeros((frames, 2), dtype=engine.dtype)
                    engine._process_frame(outdata, frames, indata)

                with sd.InputStream(
                    device=sd_in,
                    samplerate=sample_rate,
                    blocksize=blocksize,
                    channels=2,
                    latency="high",
                    callback=_input_only_callback,
                ):
                    while mpx_state["running"] and not shutdown_event.is_set():
                        if capture_seconds and time.time() - start_time >= capture_seconds:
                            timed_out = True
                            mpx_state["running"] = False
                            rds_state["running"] = False
                            break
                        sd.sleep(100)
            else:
                block_time = blocksize / float(sample_rate)
                outdata = np.zeros((blocksize, 2), dtype=engine.dtype)
                next_tick = time.time()
                while mpx_state["running"] and not shutdown_event.is_set():
                    engine._process_frame(outdata, blocksize, None)
                    if capture_seconds and time.time() - start_time >= capture_seconds:
                        timed_out = True
                        mpx_state["running"] = False
                        rds_state["running"] = False
                        break
                    next_tick += block_time
                    sleep_for = max(0.0, next_tick - time.time())
                    time.sleep(sleep_for)
        elif mpx_state.get("source_mode") == "input" and sd_in >= 0:
            with sd.Stream(
                device=(sd_in, sd_out),
                samplerate=sample_rate,
                blocksize=blocksize,
                channels=2,
                latency="high",
                callback=engine.callback_duplex,
            ):
                start_time = time.time()
                while mpx_state["running"] and not shutdown_event.is_set():
                    if capture_seconds and time.time() - start_time >= capture_seconds:
                        timed_out = True
                        mpx_state["running"] = False
                        rds_state["running"] = False
                        break
                    sd.sleep(100)
        else:
            with sd.OutputStream(
                device=sd_out,
                samplerate=sample_rate,
                blocksize=blocksize,
                channels=2,
                latency="high",
                callback=engine.callback_output,
            ):
                start_time = time.time()
                while mpx_state["running"] and not shutdown_event.is_set():
                    if capture_seconds and time.time() - start_time >= capture_seconds:
                        timed_out = True
                        mpx_state["running"] = False
                        rds_state["running"] = False
                        break
                    sd.sleep(100)
    except Exception as exc:
        logger.error("Audio Error: %s", exc)
        mpx_state["running"] = False
        rds_state["running"] = False
    finally:
        logger.info("StereoFool: audio stopped")
        if engine.audio_in:
            engine.audio_in.stop()
        engine.close()
        if capture:
            capture.stop()
        if monitor:
            monitor.stop()
    return timed_out


def _run_audio_wrapper(capture_seconds: float | None = None) -> None:
    timed_out = False
    try:
        timed_out = run_audio(capture_seconds=capture_seconds)
    finally:
        if capture_seconds and timed_out:
            capture_complete_event.set()
        global audio_thread
        with audio_thread_lock:
            audio_thread = None


def launch_audio_thread(capture_seconds: float | None = None) -> bool:
    global audio_thread
    with audio_thread_lock:
        if audio_thread and audio_thread.is_alive():
            return False
        audio_thread = threading.Thread(
            target=_run_audio_wrapper, args=(capture_seconds,), daemon=True
        )
        audio_thread.start()
        return True


def stop_audio_thread(timeout: float = 1.0) -> None:
    global audio_thread
    mpx_state["running"] = False
    rds_state["running"] = False
    with audio_thread_lock:
        thread = audio_thread
    if thread and thread.is_alive():
        thread.join(timeout)
    with audio_thread_lock:
        if audio_thread and not audio_thread.is_alive():
            audio_thread = None


def request_audio_restart(reason: str, capture_seconds: float | None) -> None:
    if not mpx_state.get("running"):
        return
    with restart_lock:
        if restart_state["pending"]:
            return
        restart_state["pending"] = True

    def _restart() -> None:
        logger.info("StereoFool: restarting audio (%s)", reason)
        stop_audio_thread(timeout=1.5)
        time.sleep(0.2)
        mpx_state["running"] = True
        rds_state["running"] = True
        launch_audio_thread(capture_seconds=capture_seconds)
        with restart_lock:
            restart_state["pending"] = False

    threading.Thread(target=_restart, daemon=True).start()


def text_updater_loop() -> None:
    while not shutdown_event.is_set():
        if rds_state["running"]:
            for key in ["ps_dynamic", "ps_long_32", "rt_text", "rt_a", "rt_b", "ptyn"]:
                if key in rds_state and "\\" in rds_state[key]:
                    result = parse_text_source(rds_state[key])
                    if result is not None:
                        resolved_cache[key] = result
        time.sleep(4.0)


def refresh_monitor_snapshot() -> dict[str, Any]:
    with monitor_lock:
        monitor_data["heartbeat"] = int(time.time() * 1000)
        if rds_state["running"]:
            monitor_data["af"] = rds_state["af_list"]
            monitor_data["pty_idx"] = rds_state["pty"]
            monitor_data["pi"] = rds_state["pi"]
            monitor_data["pilot_generated"] = True
            monitor_data["rds_carrier"] = bool(mpx_state.get("en_rds"))
        else:
            monitor_data.update(
                {
                    "ps": "OFF AIR",
                    "rt": "Encoder Stopped",
                    "lps": "",
                    "ptyn": "",
                    "af": "",
                    "pty_idx": 0,
                    "rt_plus_info": "",
                    "pi": "----",
                    "pilot_generated": False,
                    "rds_carrier": False,
                }
            )
        return dict(monitor_data)


def compose_worker_payload(
    monitor_snapshot: Mapping[str, Any], input_wave: Sequence[float], mpx_wave: Sequence[float]
) -> dict[str, Any]:
    with meter_lock:
        payload: dict[str, Any] = {
            "running": mpx_state["running"],
            "processing_bypass": bool(mpx_state.get("processing_bypass")),
            **monitor_snapshot,
            "heartbeat": int(time.time() * 1000),
            "input_rms": meter_state["input_rms"],
            "mpx_rms": meter_state["mpx_rms"],
            "input_peak": meter_state["input_peak"],
            "mpx_peak": meter_state["mpx_peak"],
            "input_vu": meter_state["input_vu"],
            "input_rms_l": meter_state.get("input_rms_l", 0.0),
            "input_rms_r": meter_state.get("input_rms_r", 0.0),
            "input_vu_l": meter_state.get("input_vu_l", 0.0),
            "input_vu_r": meter_state.get("input_vu_r", 0.0),
            "mpx_vu": meter_state["mpx_vu"],
            "input_pre_rms": meter_state["input_pre_rms"],
            "input_pre_peak": meter_state["input_pre_peak"],
            "input_pre_vu": meter_state["input_pre_vu"],
            "output_rms": meter_state["output_rms"],
            "output_peak": meter_state["output_peak"],
            "output_vu": meter_state["output_vu"],
            "limiter_active": meter_state["limiter_active"],
            "multiband_enabled": meter_state["multiband_enabled"],
            "multiband_active": meter_state["multiband_active"],
            "orbass_enabled": bool(mpx_state.get("orbass_enabled")),
            "stereo_widen_enabled": bool(mpx_state.get("stereo_widen_enabled")),
            "preemph_limit_enabled": meter_state["preemph_limit_enabled"],
            "preemph_limit_active": meter_state["preemph_limit_active"],
            "composite_clip_enabled": meter_state["composite_clip_enabled"],
            "composite_clip_active": meter_state["composite_clip_active"],
            "capture_complete": capture_complete_event.is_set(),
        }
    payload["input_wave"] = list(input_wave)
    payload["mpx_wave"] = list(mpx_wave)
    return payload


def _queue_put_latest(work_queue: Any, item: Any) -> None:
    try:
        work_queue.put_nowait(item)
        return
    except queue.Full:
        try:
            work_queue.get_nowait()
        except Exception:
            return
        try:
            work_queue.put_nowait(item)
        except Exception:
            pass
    except Exception:
        pass


def _decimate_wave(samples: Sequence[float], max_points: int = 192) -> list[float]:
    if len(samples) <= max_points:
        return list(samples)
    step = max(1, len(samples) // max_points)
    return [float(samples[i]) for i in range(0, len(samples), step)][:max_points]


def telemetry_loop(telemetry_queue: Any) -> None:
    meta_counter = 0
    wave_counter = 0
    monitor_snapshot = refresh_monitor_snapshot()
    last_input_wave: list[float] = []
    last_mpx_wave: list[float] = []
    while not shutdown_event.is_set():
        if meta_counter <= 0:
            monitor_snapshot = refresh_monitor_snapshot()
            meta_counter = 1
        meta_counter -= 1
        if wave_counter <= 0:
            with wave_lock:
                last_input_wave = _decimate_wave(wave_state["input_wave"])
                last_mpx_wave = _decimate_wave(wave_state["mpx_wave"])
            wave_counter = 1
        wave_counter -= 1
        payload = compose_worker_payload(monitor_snapshot, last_input_wave, last_mpx_wave)
        _queue_put_latest(telemetry_queue, payload)
        time.sleep(TELEMETRY_INTERVAL_SECONDS)


def control_apply_loop() -> None:
    while not shutdown_event.is_set():
        _flush_pending_updates()
        time.sleep(CONTROL_APPLY_INTERVAL_SECONDS)


def worker_main(command_queue: Any, telemetry_queue: Any) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    logger.info("StereoFool audio worker starting")
    _apply_audio_priority_profile("worker")
    global pending_dsp_reset
    shutdown_event.clear()
    capture_complete_event.clear()
    with state_update_lock:
        pending_mpx_updates.clear()
        pending_rds_updates.clear()
        pending_dsp_reset = False
    threading.Thread(target=text_updater_loop, daemon=True).start()
    threading.Thread(target=telemetry_loop, args=(telemetry_queue,), daemon=True).start()
    threading.Thread(target=control_apply_loop, daemon=True).start()

    while not shutdown_event.is_set():
        try:
            message = command_queue.get(timeout=0.2)
        except queue.Empty:
            continue
        except Exception:
            time.sleep(0.05)
            continue
        if not isinstance(message, Mapping):
            continue
        msg_type = str(message.get("type", ""))
        if msg_type == "sync_state":
            _queue_state_update(
                cast(Mapping[str, Any], message.get("mpx", {})),
                cast(Mapping[str, Any], message.get("rds", {})),
            )
            _flush_pending_updates()
            continue
        if msg_type == "update_state":
            _queue_state_update(
                cast(Mapping[str, Any], message.get("mpx", {})),
                cast(Mapping[str, Any], message.get("rds", {})),
            )
            continue
        if msg_type == "dsp_reset":
            _queue_dsp_reset()
            continue
        if msg_type == "start":
            _flush_pending_updates()
            capture_complete_event.clear()
            mpx_state["running"] = True
            rds_state["running"] = True
            launch_audio_thread(capture_seconds=cast(float | None, message.get("capture_seconds")))
            continue
        if msg_type == "stop":
            stop_audio_thread(timeout=float(message.get("timeout", 1.0)))
            continue
        if msg_type == "restart":
            _flush_pending_updates()
            capture_complete_event.clear()
            reason = str(message.get("reason", "config change"))
            capture_seconds = cast(float | None, message.get("capture_seconds"))
            request_audio_restart(reason, capture_seconds)
            continue
        if msg_type == "shutdown":
            shutdown_event.set()
            stop_audio_thread(timeout=1.5)
            break

    stop_audio_thread(timeout=1.0)
    logger.info("StereoFool audio worker stopped")
