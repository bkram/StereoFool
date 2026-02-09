import argparse
import configparser
import hashlib
import ipaddress
import logging
import os
import queue
import signal
import sys
import threading
import time
import wave
from collections import deque
from pathlib import Path
from typing import Any, Mapping, Sequence, TypedDict, cast

if __package__ in (None, ""):
    sys.path.append(os.path.dirname(os.path.dirname(__file__)))

import numpy as np
import sounddevice as sd
from flask import Flask, jsonify, request, redirect, session, url_for
from flask_socketio import SocketIO, disconnect, join_room
from scipy import signal as dsp_signal

from stereofool.constants import (
    BLOCKSIZE,
    DEFAULT_SAMPLE_RATE,
    FALLBACK_SAMPLE_RATE,
    PTY_LIST,
)
from stereofool.state import (
    dsp_control,
    meter_lock,
    meter_state,
    monitor_data,
    monitor_lock,
    mpx_state,
    rds_default_state,
    rds_state,
    resolved_cache,
    wave_lock,
    wave_state,
)
from stereofool.audio import FMEngine
from stereofool.rds import parse_text_source
from stereofool.ui import LOGIN_HTML, MPX_HTML


APP_VERSION = "0.5"
app = Flask(__name__)
CONFIG_FILE = "stereofool.ini"
app.secret_key = os.environ.get("STEREOFOOL_SECRET", os.urandom(24).hex())
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")
MPX_TEMPLATE = app.jinja_env.from_string(MPX_HTML)
LOGIN_TEMPLATE = app.jinja_env.from_string(LOGIN_HTML)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("stereofool")

allow_subnets: list[str] = ["127.0.0.0/8", "::1/128"]
class ServerConfig(TypedDict):
    port: int | None
    allow_subnets: list[str]


auth_config: dict[str, str] = {"user": "admin", "pass": "pass"}
server_config: ServerConfig = {
    "port": None,
    "allow_subnets": list(allow_subnets),
}

RESTART_KEYS = {
    "device_out_idx",
    "device_in_idx",
    "source_mode",
    "blocksize",
    "processing_rate_hz",
    "wav_record_enabled",
    "wav_record_path",
    "monitor_enabled",
    "monitor_device_idx",
    "monitor_rate_hz",
    "output_enabled",
}
PROCESSING_RESET_KEYS = {
    "multiband_enabled",
    "stereo_widen_enabled",
    "preemphasis_limit_enabled",
    "composite_clip_enabled",
    "limit_mpx",
    "limit_lookahead_enabled",
    "processing_bypass",
}
audio_thread_lock = threading.Lock()
audio_thread: threading.Thread | None = None
restart_lock = threading.Lock()
restart_state = {"pending": False}
capture_seconds_cli: float | None = None
config_save_lock = threading.Lock()
config_save_event = threading.Event()
config_save_state = {"pending": False, "last_request": 0.0}
config_file_lock = threading.Lock()
monitor_clients_lock = threading.Lock()
monitor_clients = 0
monitor_room = "monitor_clients"
monitor_sid_to_session: dict[str, str] = {}
monitor_session_to_sid: dict[str, str] = {}
ui_cache_lock = threading.Lock()
ui_state_revision = 0
ui_cache = {"key": None, "html": ""}

PREFERRED_HOSTAPIS = {
    "win": ["Windows DirectSound", "MME"],
    "darwin": ["Core Audio"],
    "linux": ["ALSA", "PulseAudio", "JACK"],
}
MONITOR_EMIT_INTERVAL = 0.1
MONITOR_WAVE_UPDATE_EVERY = 2
MONITOR_META_UPDATE_EVERY = 5


class WavCapture:
    def __init__(self, path, source_rate, target_rate=DEFAULT_SAMPLE_RATE):
        self.path = path
        self.source_rate = int(source_rate)
        self.target_rate = int(target_rate)
        self.queue: queue.Queue[np.ndarray] = queue.Queue(maxsize=12)
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._writer_loop, daemon=True)
        self.dropped = 0

    def start(self):
        self.thread.start()

    def push(self, data):
        if self.stop_event.is_set():
            return
        try:
            chunk = np.asarray(data, dtype=np.float32)
            self.queue.put_nowait(chunk.copy())
        except queue.Full:
            self.dropped += 1

    def stop(self, timeout=1.0):
        self.stop_event.set()
        self.thread.join(timeout=timeout)
        if self.dropped:
            logger.info("StereoFool: WAV capture dropped %s blocks", self.dropped)

    def _writer_loop(self):
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
    def __init__(self, device_idx, sample_rate, blocksize=BLOCKSIZE):
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
        self.stream = None
        self.waiting_prefill = True
        self.queue_drop_frames = 0
        self.queue_underruns = 0

    def start(self):
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

    def stop(self):
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

    def push(self, data):
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

    def _callback(self, outdata, frames, _time_info, _status):
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
                    self._status_counts[key] = self._status_counts.get(key, 0) + 1
                    seen_flag = True
            except Exception:
                continue
        if not seen_flag:
            key = str(status)
            self._status_counts[key] = self._status_counts.get(key, 0) + 1


def _normalize_hostapi_name(name):
    return "".join(ch for ch in str(name).lower() if ch.isalnum())


def resolve_hostapi_filter(apis):
    hostapi_override = os.environ.get("STEREOFOOL_HOSTAPI", "").strip()
    available_names = [str(a.get("name", "")) for a in apis]
    available_norm = {_normalize_hostapi_name(name): name for name in available_names}
    if hostapi_override:
        alias_map = {
            "wasapi": "windowswasapi",
            "wdmks": "windowswdmks",
            "kernelstreaming": "windowswdmks",
            "ks": "windowswdmks",
            "mme": "mme",
            "directsound": "windowsdirectsound",
            "dsound": "windowsdirectsound",
            "asio": "asio",
            "coreaudio": "coreaudio",
            "alsa": "alsa",
            "pulseaudio": "pulseaudio",
            "jack": "jack",
        }
        requested = []
        for raw in hostapi_override.split(","):
            token = raw.strip()
            if not token:
                continue
            token_norm = _normalize_hostapi_name(token)
            token_norm = alias_map.get(token_norm, token_norm)
            requested.append(token_norm)
        matches = {norm for norm in requested if norm in available_norm}
        if not matches:
            logger.warning(
                "StereoFool: STEREOFOOL_HOSTAPI=%r matched no host APIs; available=%s",
                hostapi_override,
                ", ".join(available_names),
            )
        # Explicit override is strict: no silent fallback to all APIs.
        return matches, True
    if sys.platform.startswith("win"):
        platform_key = "win"
    elif sys.platform.startswith("linux"):
        platform_key = "linux"
    else:
        platform_key = sys.platform
    preferred = PREFERRED_HOSTAPIS.get(platform_key, [])
    matches = []
    for name in preferred:
        norm = _normalize_hostapi_name(name)
        if norm in available_norm:
            matches.append(norm)
    # Built-in preferred filter is best-effort and can fall back.
    return set(matches), False


def _parse_subnets(value):
    if not value:
        return []
    if isinstance(value, list):
        raw = value
    else:
        raw = [v.strip() for v in str(value).split(",") if v.strip()]
    subnets = []
    for entry in raw:
        try:
            ipaddress.ip_network(entry, strict=False)
            subnets.append(entry)
        except ValueError:
            continue
    return subnets


def _client_ip():
    return request.headers.get("X-Forwarded-For", request.remote_addr or "").split(",")[0].strip()


def _is_allowed_client():
    if not allow_subnets:
        return True
    ip_str = _client_ip()
    try:
        ip_addr = ipaddress.ip_address(ip_str)
    except ValueError:
        return False
    for net in allow_subnets:
        try:
            if ip_addr in ipaddress.ip_network(net, strict=False):
                return True
        except ValueError:
            continue
    return False


def _hash_password(password):
    if not password:
        return ""
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 200_000)
    return f"sha256${salt.hex()}${dk.hex()}"


def _verify_password(password, stored):
    if not stored:
        return False
    if stored.startswith("sha256$"):
        parts = stored.split("$", 2)
        if len(parts) != 3:
            return False
        salt = bytes.fromhex(parts[1])
        expected = parts[2]
        dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 200_000)
        return dk.hex() == expected
    return password == stored


def _device_supports_output(device_idx, samplerate):
    try:
        sd.check_output_settings(device=device_idx, samplerate=samplerate)
        return True
    except Exception:
        return False


def _device_supports_input(device_idx, samplerate):
    try:
        sd.check_input_settings(device=device_idx, samplerate=samplerate)
        return True
    except Exception:
        return False


device_cache: dict[str, list[dict[str, Any]]] = {"inputs": [], "outputs": []}


def get_valid_devices(force_refresh=False):
    valid_outputs = []
    if mpx_state.get("running") and not force_refresh:
        return device_cache["outputs"]
    valid_outputs = list(device_cache["outputs"])
    try:
        devs = cast(Sequence[Mapping[str, Any]], sd.query_devices())
        apis = cast(Sequence[Mapping[str, Any]], sd.query_hostapis())
        hostapi_filter, strict_filter = resolve_hostapi_filter(apis)

        def collect_outputs(filter_set):
            if strict_filter and not filter_set:
                return []
            outputs = []
            for i, d in enumerate(devs):
                d_info = cast(Mapping[str, Any], d)
                api_name = str(apis[int(d_info["hostapi"])]["name"])
                if filter_set and _normalize_hostapi_name(api_name) not in filter_set:
                    continue
                try:
                    if int(d_info["max_output_channels"]) > 0:
                        if _device_supports_output(
                            i, DEFAULT_SAMPLE_RATE
                        ) or _device_supports_output(i, FALLBACK_SAMPLE_RATE):
                            outputs.append({"index": i, "name": f"{d_info['name']} ({api_name})"})
                except Exception:
                    continue
            return outputs

        valid_outputs = collect_outputs(hostapi_filter)
        if hostapi_filter and not valid_outputs and not strict_filter:
            valid_outputs = collect_outputs(set())
    except Exception as exc:
        logger.warning("Device Error: %s", exc)
    device_cache["outputs"] = valid_outputs
    return valid_outputs


def get_valid_input_devices(force_refresh=False):
    valid_inputs = []
    if mpx_state.get("running") and not force_refresh:
        return device_cache["inputs"]
    valid_inputs = list(device_cache["inputs"])
    try:
        devs = cast(Sequence[Mapping[str, Any]], sd.query_devices())
        apis = cast(Sequence[Mapping[str, Any]], sd.query_hostapis())
        hostapi_filter, strict_filter = resolve_hostapi_filter(apis)

        def collect_inputs(filter_set):
            if strict_filter and not filter_set:
                return []
            inputs = []
            for i, d in enumerate(devs):
                d_info = cast(Mapping[str, Any], d)
                api_name = str(apis[int(d_info["hostapi"])]["name"])
                if filter_set and _normalize_hostapi_name(api_name) not in filter_set:
                    continue
                try:
                    if int(d_info["max_input_channels"]) > 0:
                        if _device_supports_input(i, DEFAULT_SAMPLE_RATE) or _device_supports_input(
                            i, FALLBACK_SAMPLE_RATE
                        ):
                            inputs.append({"index": i, "name": f"{d_info['name']} ({api_name})"})
                except Exception:
                    continue
            return inputs

        valid_inputs = collect_inputs(hostapi_filter)
        if hostapi_filter and not valid_inputs and not strict_filter:
            valid_inputs = collect_inputs(set())
    except Exception as exc:
        logger.warning("Device Error: %s", exc)
    device_cache["inputs"] = valid_inputs
    return valid_inputs


def normalize_device_indices():
    outputs = get_valid_devices(force_refresh=True)
    inputs = get_valid_input_devices(force_refresh=True)
    valid_outputs = {d["index"] for d in outputs}
    valid_inputs = {d["index"] for d in inputs}

    current_out = mpx_state.get("device_out_idx", -1)
    if current_out is not None and current_out >= 0 and current_out not in valid_outputs:
        if outputs:
            mpx_state["device_out_idx"] = outputs[0]["index"]
            logger.warning(
                "StereoFool: output device %s not usable; selecting %s",
                current_out,
                outputs[0]["name"],
            )
        else:
            mpx_state["device_out_idx"] = -1
            logger.warning(
                "StereoFool: output device %s not usable; disabling output",
                current_out,
            )

    current_in = mpx_state.get("device_in_idx", -1)
    if current_in is not None and current_in >= 0 and current_in not in valid_inputs:
        if mpx_state.get("source_mode") == "input" and inputs:
            mpx_state["device_in_idx"] = inputs[0]["index"]
            logger.warning(
                "StereoFool: input device %s not usable; selecting %s",
                current_in,
                inputs[0]["name"],
            )
        else:
            mpx_state["device_in_idx"] = -1
            logger.warning(
                "StereoFool: input device %s not usable; disabling input",
                current_in,
            )


def select_sample_rate(device_out_idx, device_in_idx):
    for rate in (DEFAULT_SAMPLE_RATE, FALLBACK_SAMPLE_RATE):
        try:
            sd.check_output_settings(device=device_out_idx, samplerate=rate)
            if device_in_idx is not None and device_in_idx >= 0:
                sd.check_input_settings(device=device_in_idx, samplerate=rate)
            return rate
        except Exception:
            continue
    return FALLBACK_SAMPLE_RATE


def resolve_blocksize():
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


# --- RDS state (full) ---


def load_config():
    config = configparser.ConfigParser(interpolation=None)
    if os.path.exists(CONFIG_FILE):
        config.read(CONFIG_FILE)
        if "RDS" in config:
            for k in rds_state:
                if k in config["RDS"]:
                    val = config["RDS"][k]
                    if isinstance(rds_default_state[k], bool):
                        rds_state[k] = val == "True"
                    elif isinstance(rds_default_state[k], int) and not isinstance(
                        rds_default_state[k], bool
                    ):
                        rds_state[k] = int(val)
                    elif isinstance(rds_default_state[k], float):
                        rds_state[k] = float(val)
                    else:
                        rds_state[k] = val
        if "MPX" in config:
            for k in mpx_state:
                if k in config["MPX"]:
                    val = config["MPX"][k]
                    if isinstance(mpx_state[k], bool):
                        mpx_state[k] = val == "True"
                    elif isinstance(mpx_state[k], int) and not isinstance(mpx_state[k], bool):
                        mpx_state[k] = int(val)
                    elif isinstance(mpx_state[k], float):
                        mpx_state[k] = float(val)
                    else:
                        mpx_state[k] = val
        if "AUTH" in config:
            auth_config["user"] = config["AUTH"].get("user", auth_config["user"])
            auth_config["pass"] = config["AUTH"].get("pass", auth_config["pass"])
        if "SYSTEM" in config:
            if "port" in config["SYSTEM"]:
                server_config["port"] = config["SYSTEM"].getint("port", fallback=None)
            if "allow_subnets" in config["SYSTEM"]:
                parsed = _parse_subnets(config["SYSTEM"].get("allow_subnets", ""))
                if parsed:
                    allow_subnets[:] = parsed
                server_config["allow_subnets"] = list(allow_subnets)
        if "INTERFACES" in config:
            if "device_out_idx" in config["INTERFACES"]:
                mpx_state["device_out_idx"] = config["INTERFACES"].getint(
                    "device_out_idx", fallback=mpx_state["device_out_idx"]
                )
            if "device_in_idx" in config["INTERFACES"]:
                mpx_state["device_in_idx"] = config["INTERFACES"].getint(
                    "device_in_idx", fallback=mpx_state["device_in_idx"]
                )
            if "source_mode" in config["INTERFACES"]:
                mpx_state["source_mode"] = config["INTERFACES"].get(
                    "source_mode", fallback=mpx_state["source_mode"]
                )
            if "wav_record_enabled" in config["INTERFACES"]:
                mpx_state["wav_record_enabled"] = config["INTERFACES"].getboolean(
                    "wav_record_enabled", fallback=mpx_state["wav_record_enabled"]
                )
            if "wav_record_path" in config["INTERFACES"]:
                mpx_state["wav_record_path"] = config["INTERFACES"].get(
                    "wav_record_path", fallback=mpx_state["wav_record_path"]
                )
            if "monitor_enabled" in config["INTERFACES"]:
                mpx_state["monitor_enabled"] = config["INTERFACES"].getboolean(
                    "monitor_enabled", fallback=mpx_state["monitor_enabled"]
                )
            if "monitor_device_idx" in config["INTERFACES"]:
                mpx_state["monitor_device_idx"] = config["INTERFACES"].getint(
                    "monitor_device_idx", fallback=mpx_state["monitor_device_idx"]
                )
            if "monitor_rate_hz" in config["INTERFACES"]:
                mpx_state["monitor_rate_hz"] = config["INTERFACES"].getint(
                    "monitor_rate_hz", fallback=mpx_state["monitor_rate_hz"]
                )
            if "blocksize" in config["INTERFACES"]:
                mpx_state["blocksize"] = config["INTERFACES"].getint(
                    "blocksize", fallback=mpx_state["blocksize"]
                )
    rds_state["auto_start"] = True


def _coerce_bool(val):
    if isinstance(val, str):
        return val.strip().lower() in {"true", "1", "yes", "on"}
    return bool(val)


def _write_config_now():
    with config_file_lock:
        config = configparser.ConfigParser(interpolation=None)
        if os.path.exists(CONFIG_FILE):
            config.read(CONFIG_FILE)
        rds_state["auto_start"] = True
        rds_config = {
            k: str(v)
            for k, v in rds_state.items()
            if k
            not in {
                "device_out_idx",
                "device_in_idx",
                "running",
            }
        }
        mpx_config = {
            k: str(v)
            for k, v in mpx_state.items()
            if k
            not in {
                "device_out_idx",
                "device_in_idx",
                "source_mode",
                "wav_record_enabled",
                "wav_record_path",
                "monitor_enabled",
                "monitor_device_idx",
                "monitor_rate_hz",
                "blocksize",
                "processing_bypass",
                "running",
            }
        }
        config["RDS"] = rds_config
        config["MPX"] = mpx_config
        stored_pass = auth_config.get("pass", "admin")
        if stored_pass and not stored_pass.startswith("sha256$"):
            stored_pass = _hash_password(stored_pass)
            auth_config["pass"] = stored_pass
        config["AUTH"] = {
            "user": auth_config.get("user", "admin"),
            "pass": stored_pass,
        }
        if not config.has_section("SYSTEM"):
            config.add_section("SYSTEM")
        config["SYSTEM"]["allow_subnets"] = ", ".join(allow_subnets)
        if not config.has_section("INTERFACES"):
            config.add_section("INTERFACES")
        config["INTERFACES"]["device_out_idx"] = str(mpx_state.get("device_out_idx", 0))
        config["INTERFACES"]["device_in_idx"] = str(mpx_state.get("device_in_idx", -1))
        config["INTERFACES"]["source_mode"] = str(mpx_state.get("source_mode", "input"))
        config["INTERFACES"]["wav_record_enabled"] = str(
            mpx_state.get("wav_record_enabled", False)
        )
        config["INTERFACES"]["wav_record_path"] = str(mpx_state.get("wav_record_path", "output.wav"))
        config["INTERFACES"]["monitor_enabled"] = str(mpx_state.get("monitor_enabled", False))
        config["INTERFACES"]["monitor_device_idx"] = str(mpx_state.get("monitor_device_idx", -1))
        config["INTERFACES"]["monitor_rate_hz"] = str(mpx_state.get("monitor_rate_hz", 48000))
        config["INTERFACES"]["blocksize"] = str(mpx_state.get("blocksize", BLOCKSIZE))
        if server_config.get("port"):
            config["SYSTEM"]["port"] = str(server_config["port"])
        with open(CONFIG_FILE, "w") as f:
            config.write(f)


def _bump_ui_revision():
    global ui_state_revision
    with ui_cache_lock:
        ui_state_revision += 1


def _config_writer_loop():
    while True:
        config_save_event.wait()
        while True:
            with config_save_lock:
                pending = bool(config_save_state["pending"])
                wait_remaining = 0.35 - (time.monotonic() - float(config_save_state["last_request"]))
            if not pending:
                config_save_event.clear()
                break
            if wait_remaining > 0:
                # Coalesce rapid UI updates into one config write.
                time.sleep(min(wait_remaining, 0.1))
                continue
            try:
                _write_config_now()
            except Exception:
                logger.exception("StereoFool: failed to save config")
                time.sleep(0.2)
            finally:
                with config_save_lock:
                    elapsed = time.monotonic() - float(config_save_state["last_request"])
                    if elapsed >= 0.35:
                        config_save_state["pending"] = False


def save_config(debounce=False):
    if not debounce:
        _write_config_now()
        return
    with config_save_lock:
        config_save_state["pending"] = True
        config_save_state["last_request"] = time.monotonic()
    config_save_event.set()


def sig_abort(sig, _frame):
    rds_state["running"] = False
    mpx_state["running"] = False
    save_config()
    os._exit(0)


signal.signal(signal.SIGINT, sig_abort)


# --- RDS helpers ---


def text_updater_loop():
    while True:
        if rds_state["running"]:
            for k in ["ps_dynamic", "ps_long_32", "rt_text", "rt_a", "rt_b", "ptyn"]:
                if k in rds_state and "\\" in rds_state[k]:
                    result = parse_text_source(rds_state[k])
                    if result is not None:
                        resolved_cache[k] = result
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


def compose_monitor_payload(
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
            "stereo_widen_enabled": bool(mpx_state.get("stereo_widen_enabled")),
            "preemph_limit_enabled": meter_state["preemph_limit_enabled"],
            "preemph_limit_active": meter_state["preemph_limit_active"],
            "composite_clip_enabled": meter_state["composite_clip_enabled"],
            "composite_clip_active": meter_state["composite_clip_active"],
        }
    payload["input_wave"] = list(input_wave)
    payload["mpx_wave"] = list(mpx_wave)
    return payload


def monitor_pusher_loop():
    meta_counter = 0
    wave_counter = 0
    monitor_snapshot = refresh_monitor_snapshot()
    last_input_wave: list[float] = []
    last_mpx_wave: list[float] = []
    while True:
        with monitor_clients_lock:
            active_clients = monitor_clients
        if active_clients <= 0:
            time.sleep(MONITOR_EMIT_INTERVAL)
            continue
        if meta_counter <= 0:
            monitor_snapshot = refresh_monitor_snapshot()
            meta_counter = MONITOR_META_UPDATE_EVERY
        meta_counter -= 1

        if wave_counter <= 0:
            with wave_lock:
                last_input_wave = wave_state["input_wave"]
                last_mpx_wave = wave_state["mpx_wave"]
            wave_counter = MONITOR_WAVE_UPDATE_EVERY
        wave_counter -= 1

        payload = compose_monitor_payload(monitor_snapshot, last_input_wave, last_mpx_wave)
        socketio.emit("monitor", payload, to=monitor_room)
        time.sleep(MONITOR_EMIT_INTERVAL)


threading.Thread(target=text_updater_loop, daemon=True).start()
threading.Thread(target=monitor_pusher_loop, daemon=True).start()
threading.Thread(target=_config_writer_loop, daemon=True).start()


def run_audio(capture_seconds=None):
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
            logger.warning(
                "StereoFool: stereo subcarrier band will be truncated at this sample rate"
            )
    capture = None
    monitor = None
    if mpx_state.get("wav_record_enabled"):
        path = str(mpx_state.get("wav_record_path", "mpx_capture.wav")).strip()
        if path:
            capture = WavCapture(path, sample_rate, DEFAULT_SAMPLE_RATE)
            capture.start()
            logger.info(
                "StereoFool: WAV capture enabled (%s, %s Hz)",
                path,
                DEFAULT_SAMPLE_RATE,
            )
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
        logger.info(
            "StereoFool: monitor device matches output device; disabling MPX output for monitor mode"
        )
    monitor_blocksize = max(1, int(round(blocksize * (monitor_rate / float(sample_rate)))))
    if monitor_enabled and monitor_device >= 0:
        monitor = MonitorOutput(monitor_device, monitor_rate, blocksize=monitor_blocksize)
        monitor.start()
        logger.info(
            "StereoFool: monitor output enabled (device=%s, rate=%s)",
            monitor_device,
            monitor_rate,
        )
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
            devs = sd.query_devices()
            out_name = (
                devs[sd_out]["name"]
                if output_enabled and sd_out is not None and sd_out >= 0
                else "Disabled"
            )
            in_name = devs[sd_in]["name"] if sd_in is not None and sd_in >= 0 else "None"
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

                def _input_only_callback(indata, frames, _time_info, _status):
                    if _status:
                        now = time.monotonic()
                        last = last_status_log[0]
                        if now - last >= 1.0:
                            logger.warning(
                                "StereoFool: input-only stream status: %s", _status
                            )
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
                    while mpx_state["running"]:
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
                while mpx_state["running"]:
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
                while mpx_state["running"]:
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
                while mpx_state["running"]:
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


def _run_audio_wrapper(capture_seconds=None):
    timed_out = False
    try:
        timed_out = run_audio(capture_seconds=capture_seconds)
    finally:
        global audio_thread
        with audio_thread_lock:
            audio_thread = None
        if capture_seconds and timed_out:
            logger.info("StereoFool: capture complete, exiting")
            os._exit(0)


def launch_audio_thread(capture_seconds=None):
    global audio_thread
    with audio_thread_lock:
        if audio_thread and audio_thread.is_alive():
            return False
        audio_thread = threading.Thread(
            target=_run_audio_wrapper, args=(capture_seconds,), daemon=True
        )
        audio_thread.start()
        return True


def stop_audio_thread(timeout=1.0):
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


def auto_start_if_enabled():
    if rds_state.get("auto_start") and not mpx_state.get("running"):
        mpx_state["running"] = True
        rds_state["running"] = True
        launch_audio_thread(capture_seconds=capture_seconds_cli)


def request_audio_restart(reason):
    if not mpx_state.get("running"):
        return
    with restart_lock:
        if restart_state["pending"]:
            return
        restart_state["pending"] = True

    def _restart():
        logger.info("StereoFool: restarting audio (%s)", reason)
        stop_audio_thread(timeout=1.5)
        time.sleep(0.2)
        mpx_state["running"] = True
        rds_state["running"] = True
        launch_audio_thread(capture_seconds=capture_seconds_cli)
        with restart_lock:
            restart_state["pending"] = False

    threading.Thread(target=_restart, daemon=True).start()


# --- UI routes ---


@app.route("/")
def index():
    if not session.get("auth"):
        return redirect(url_for("login"))
    outputs = get_valid_devices()
    inputs = get_valid_input_devices()
    with ui_cache_lock:
        revision = ui_state_revision
    cache_key = (
        revision,
        tuple((int(d["index"]), str(d["name"])) for d in inputs),
        tuple((int(d["index"]), str(d["name"])) for d in outputs),
    )
    with ui_cache_lock:
        if ui_cache["key"] == cache_key and ui_cache["html"]:
            return ui_cache["html"]
    html = MPX_TEMPLATE.render(
        inputs=inputs,
        outputs=outputs,
        state=mpx_state,
        rds_state=rds_state,
        pty_list=PTY_LIST,
        auth_config=auth_config,
        server_config=server_config,
        app_version=APP_VERSION,
    )
    with ui_cache_lock:
        ui_cache["key"] = cache_key
        ui_cache["html"] = html
    return html


@app.route("/rds")
def rds_ui():
    return redirect(url_for("index"))


@app.route("/mpx")
def mpx_ui():
    return redirect(url_for("index"))


@app.route("/login", methods=["GET", "POST"])
def login():
    msg = ""
    u = ""
    p = ""
    if request.method == "POST":
        u = request.form.get("user", "")
        p = request.form.get("pass", "")
        if u == auth_config.get("user") and _verify_password(p, auth_config.get("pass", "")):
            session["auth"] = True
            return redirect(url_for("index"))
        msg = "Invalid credentials"
    return LOGIN_TEMPLATE.render(msg=msg, user=auth_config.get("user", ""), app_version=APP_VERSION)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.before_request
def enforce_allowlist():
    if request.endpoint in {"static", "login"}:
        return None
    if _is_allowed_client():
        return None
    return ("forbidden", 403)


@app.route("/settings", methods=["POST"])
def save_settings():
    if not session.get("auth"):
        return ("unauthorized", 401)
    data = request.get_json(silent=True) or {}
    user = str(data.get("user", "")).strip()
    password = str(data.get("password", "")).strip()
    parsed_subnets = _parse_subnets(data.get("allow_subnets", ""))
    if user:
        auth_config["user"] = user
    if password:
        auth_config["pass"] = _hash_password(password)
    if parsed_subnets:
        allow_subnets[:] = parsed_subnets
        server_config["allow_subnets"] = list(allow_subnets)
    session["auth"] = True
    _bump_ui_revision()
    save_config()
    return ("ok", 200)


@app.route("/monitor_snapshot")
def monitor_snapshot():
    if not session.get("auth"):
        return ("unauthorized", 401)
    snapshot = refresh_monitor_snapshot()
    with wave_lock:
        input_wave = list(wave_state["input_wave"])
        mpx_wave = list(wave_state["mpx_wave"])
    payload = compose_monitor_payload(snapshot, input_wave, mpx_wave)
    return jsonify(payload)


@socketio.on("connect")
def handle_connect():
    global monitor_clients
    if not session.get("auth"):
        return
    sid = cast(str, getattr(request, "sid", ""))
    cookie_name = app.config.get("SESSION_COOKIE_NAME", "session")
    session_cookie = request.cookies.get(cookie_name, "")
    prior_sid = None
    with monitor_clients_lock:
        prior_sid = monitor_session_to_sid.get(session_cookie) if session_cookie else None
        if session_cookie:
            monitor_session_to_sid[session_cookie] = sid
            monitor_sid_to_session[sid] = session_cookie
        monitor_clients += 1
    join_room(monitor_room)
    if prior_sid and prior_sid != sid:
        try:
            disconnect(sid=prior_sid)
        except Exception:
            pass


@socketio.on("disconnect")
def handle_disconnect():
    global monitor_clients
    sid = cast(str, getattr(request, "sid", ""))
    with monitor_clients_lock:
        sess_key = monitor_sid_to_session.pop(sid, None)
        if sess_key and monitor_session_to_sid.get(sess_key) == sid:
            del monitor_session_to_sid[sess_key]
        monitor_clients = max(0, monitor_clients - 1)


@socketio.on("update")
def handle_update(data):
    if not session.get("auth"):
        return
    changed = False
    changes = {}
    for key, val in data.items():
        if key in rds_state:
            try:
                if isinstance(rds_state[key], bool):
                    new_val = _coerce_bool(val)
                    if new_val != rds_state[key]:
                        changes[key] = new_val
                    rds_state[key] = new_val
                elif isinstance(rds_state[key], float):
                    new_val = float(val)
                    if new_val != rds_state[key]:
                        changes[key] = new_val
                    rds_state[key] = new_val
                elif isinstance(rds_state[key], int) and not isinstance(rds_state[key], bool):
                    new_val = int(val)
                    if new_val != rds_state[key]:
                        changes[key] = new_val
                    rds_state[key] = new_val
                else:
                    if val != rds_state[key]:
                        changes[key] = val
                    rds_state[key] = val
                changed = True
            except Exception:
                pass
        if key in mpx_state:
            try:
                if isinstance(mpx_state[key], bool):
                    new_val = _coerce_bool(val)
                    if new_val != mpx_state[key]:
                        changes[key] = new_val
                    mpx_state[key] = new_val
                elif isinstance(mpx_state[key], float):
                    new_val = float(val)
                    if new_val != mpx_state[key]:
                        changes[key] = new_val
                    mpx_state[key] = new_val
                elif isinstance(mpx_state[key], int) and not isinstance(mpx_state[key], bool):
                    new_val = int(val)
                    if new_val != mpx_state[key]:
                        changes[key] = new_val
                    mpx_state[key] = new_val
                else:
                    if val != mpx_state[key]:
                        changes[key] = val
                    mpx_state[key] = val
                changed = True
            except Exception:
                pass
    rds_state["auto_start"] = True
    if changed:
        if changes:
            logger.info("UI update: %s", changes)
            restart_hits = sorted(set(changes).intersection(RESTART_KEYS))
            if set(changes).intersection(PROCESSING_RESET_KEYS):
                dsp_control["reset"] = True
            if restart_hits:
                request_audio_restart(", ".join(restart_hits))
        _bump_ui_revision()
        save_config(debounce=True)


@socketio.on("control")
def handle_control(data):
    if not session.get("auth"):
        return
    if data.get("action") == "start":
        mpx_state["device_out_idx"] = int(data.get("dev_out", mpx_state["device_out_idx"]))
        if "dev_in" in data:
            mpx_state["device_in_idx"] = int(data.get("dev_in", mpx_state["device_in_idx"]))
        mpx_state["running"] = True
        rds_state["running"] = True
        _bump_ui_revision()
        save_config()
        logger.info("StereoFool: ON AIR requested")
        if not launch_audio_thread(capture_seconds=capture_seconds_cli):
            logger.info("StereoFool: audio already running")
    else:
        stop_audio_thread(timeout=1.5)
        _bump_ui_revision()
        save_config()
        logger.info("StereoFool: OFF AIR requested")


def parse_cli_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="StereoFool: composite MPX + RDS")
    parser.add_argument("--port", type=int, default=None)
    parser.add_argument("--config", type=str, default=None)
    parser.add_argument("--save-file", type=str, default=None)
    parser.add_argument("--length", type=float, default=None)
    return parser.parse_args()


def ensure_config_exists(config_path: str) -> None:
    path = Path(config_path)
    if path.exists():
        return
    config = configparser.ConfigParser(interpolation=None)
    config["SYSTEM"] = {}
    config["INTERFACES"] = {}
    config["MPX"] = {
        k: str(v)
        for k, v in mpx_state.items()
        if k
        not in {
            "device_out_idx",
            "device_in_idx",
            "source_mode",
            "wav_record_enabled",
            "wav_record_path",
            "monitor_enabled",
            "monitor_device_idx",
            "monitor_rate_hz",
        }
    }
    config["RDS"] = {k: str(v) for k, v in rds_default_state.items()}
    with path.open("w") as f:
        config.write(f)


def apply_cli_overrides(args: argparse.Namespace) -> None:
    global capture_seconds_cli
    if args.port:
        server_config["port"] = args.port
    if args.save_file:
        mpx_state["wav_record_enabled"] = True
        mpx_state["wav_record_path"] = args.save_file
    if args.length is not None and args.length <= 0:
        logger.warning("StereoFool: --length must be > 0 seconds")
        args.length = None
    if args.length is not None:
        capture_seconds_cli = args.length


def log_available_devices() -> None:
    try:
        devs = cast(Sequence[Mapping[str, Any]], sd.query_devices())
        for idx, dev in enumerate(devs):
            dev_info = cast(Mapping[str, Any], dev)
            logger.info(
                "StereoFool: device %s: %s (in=%s, out=%s)",
                idx,
                dev_info.get("name", "Unknown"),
                dev_info.get("max_input_channels", 0),
                dev_info.get("max_output_channels", 0),
            )
    except Exception as exc:
        logger.warning("StereoFool: device list unavailable: %s", exc)


def run_web_server() -> None:
    default_port = 8300
    port = server_config.get("port") or default_port
    logger.info("StereoFool: web server Socket.IO (async_mode=threading)")
    socketio.run(
        app,
        host="0.0.0.0",
        port=port,
        debug=False,
        allow_unsafe_werkzeug=True,
    )


def main() -> int:
    global CONFIG_FILE
    args = parse_cli_args()
    if args.config:
        CONFIG_FILE = args.config
        ensure_config_exists(CONFIG_FILE)
    load_config()
    logger.info("StereoFool v%s starting", APP_VERSION)
    apply_cli_overrides(args)
    log_available_devices()
    normalize_device_indices()
    auto_start_if_enabled()
    run_web_server()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
