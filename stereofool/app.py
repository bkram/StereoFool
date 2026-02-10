import argparse
import configparser
import hashlib
import ipaddress
import logging
import multiprocessing as mp
import os
import queue
import signal
import sys
import threading
import time
from pathlib import Path
from typing import Any, Mapping, Sequence, TypedDict, cast

if __package__ in (None, ""):
    sys.path.append(os.path.dirname(os.path.dirname(__file__)))

import sounddevice as sd
from flask import Flask, jsonify, request, redirect, session, url_for
from flask_socketio import SocketIO, join_room

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
    wave_lock,
    wave_state,
)
from stereofool.audio_worker import worker_main as audio_worker_main
from stereofool.ui import LOGIN_HTML, MPX_HTML


APP_VERSION = "0.6"
app = Flask(__name__)
CONFIG_FILE = "stereofool.ini"
app.secret_key = os.environ.get("STEREOFOOL_SECRET", os.urandom(24).hex())
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")
MPX_TEMPLATE = app.jinja_env.from_string(MPX_HTML)
LOGIN_TEMPLATE = app.jinja_env.from_string(LOGIN_HTML)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("stereofool")

BUILTIN_ALLOW_SUBNETS = ("127.0.0.0/8", "::1/128")
allow_subnets: list[str] = list(BUILTIN_ALLOW_SUBNETS)
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
    "audio_priority_profile",
    "output_enabled",
}
PROCESSING_RESET_KEYS = {
    "multiband_enabled",
    "multiband_mode",
    "multiband_low_hz",
    "multiband_high_hz",
    "multiband_x1_hz",
    "multiband_x2_hz",
    "multiband_x3_hz",
    "multiband_x4_hz",
    "stereo_widen_enabled",
    "preemphasis_limit_enabled",
    "composite_clip_enabled",
    "limit_mpx",
    "limit_lookahead_enabled",
    "processing_bypass",
}
audio_worker_lock = threading.Lock()
audio_worker_process: Any | None = None
audio_command_queue: Any | None = None
audio_telemetry_queue: Any | None = None
audio_worker_ready = threading.Event()
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
ui_cache_lock = threading.Lock()
ui_state_revision = 0
ui_cache = {"key": None, "html": ""}

PREFERRED_HOSTAPIS = {
    "win": ["Windows DirectSound", "MME"],
    "darwin": ["Core Audio"],
    "linux": ["ALSA", "PulseAudio", "JACK"],
}
MONITOR_EMIT_INTERVAL = 0.1
MONITOR_WAVE_UPDATE_EVERY = 1
MONITOR_META_UPDATE_EVERY = 5


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


def _merge_allow_subnets(subnets: Sequence[str]) -> list[str]:
    merged: list[str] = []
    for subnet in [*BUILTIN_ALLOW_SUBNETS, *subnets]:
        if subnet not in merged:
            merged.append(subnet)
    return merged


def _custom_allow_subnets() -> list[str]:
    return [net for net in allow_subnets if net not in BUILTIN_ALLOW_SUBNETS]


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
                allow_subnets[:] = _merge_allow_subnets(parsed)
            else:
                allow_subnets[:] = list(BUILTIN_ALLOW_SUBNETS)
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
        config["SYSTEM"]["allow_subnets"] = ", ".join(_custom_allow_subnets())
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


def _queue_put_latest(work_queue: Any, item: Any) -> bool:
    try:
        work_queue.put_nowait(item)
        return True
    except queue.Full:
        try:
            work_queue.get_nowait()
        except Exception:
            return False
        try:
            work_queue.put_nowait(item)
            return True
        except Exception:
            return False
    except Exception:
        return False


def _start_audio_worker_process() -> None:
    global audio_worker_process, audio_command_queue, audio_telemetry_queue
    with audio_worker_lock:
        if audio_worker_process and audio_worker_process.is_alive():
            return
        ctx = mp.get_context("spawn")
        command_q = ctx.Queue(maxsize=1024)
        telemetry_q = ctx.Queue(maxsize=8)
        proc = ctx.Process(
            target=audio_worker_main,
            args=(command_q, telemetry_q),
            name="stereofool-audio-worker",
            daemon=True,
        )
        proc.start()
        audio_worker_process = proc
        audio_command_queue = command_q
        audio_telemetry_queue = telemetry_q
        audio_worker_ready.set()


def _shutdown_audio_worker_process(timeout: float = 1.0) -> None:
    global audio_worker_process, audio_command_queue, audio_telemetry_queue
    with audio_worker_lock:
        proc = audio_worker_process
        command_q = audio_command_queue
    if command_q is not None:
        _queue_put_latest(command_q, {"type": "shutdown"})
    if proc and proc.is_alive():
        proc.join(timeout=timeout)
        if proc.is_alive():
            proc.terminate()
            proc.join(timeout=0.5)
    with audio_worker_lock:
        audio_worker_process = None
        audio_command_queue = None
        audio_telemetry_queue = None


def _send_audio_command(command: Mapping[str, Any]) -> bool:
    _start_audio_worker_process()
    with audio_worker_lock:
        command_q = audio_command_queue
    if command_q is None:
        return False
    return _queue_put_latest(command_q, dict(command))


def _sync_audio_worker_state() -> None:
    _send_audio_command(
        {
            "type": "sync_state",
            "mpx": dict(mpx_state),
            "rds": dict(rds_state),
        }
    )


def _apply_audio_telemetry(payload: Mapping[str, Any]) -> None:
    if capture_seconds_cli is not None and bool(payload.get("capture_complete", False)):
        logger.info("StereoFool: capture complete, exiting")
        os._exit(0)
    running = bool(payload.get("running", False))
    mpx_state["running"] = running
    rds_state["running"] = running

    monitor_keys = (
        "ps",
        "rt",
        "lps",
        "ptyn",
        "af",
        "pi",
        "pty_idx",
        "rt_plus_info",
        "heartbeat",
        "pilot_generated",
        "sample_rate",
        "device_out_name",
        "device_in_name",
        "rds_carrier",
    )
    meter_keys = (
        "input_rms",
        "mpx_rms",
        "input_peak",
        "mpx_peak",
        "input_vu",
        "input_rms_l",
        "input_rms_r",
        "input_vu_l",
        "input_vu_r",
        "mpx_vu",
        "input_pre_rms",
        "input_pre_peak",
        "input_pre_vu",
        "output_rms",
        "output_peak",
        "output_vu",
        "limiter_active",
        "multiband_enabled",
        "multiband_active",
        "preemph_limit_enabled",
        "preemph_limit_active",
        "composite_clip_enabled",
        "composite_clip_active",
    )
    with monitor_lock:
        for key in monitor_keys:
            if key in payload:
                monitor_data[key] = payload[key]
    with meter_lock:
        for key in meter_keys:
            if key in payload:
                meter_state[key] = payload[key]
    with wave_lock:
        if "input_wave" in payload and isinstance(payload["input_wave"], list):
            wave_state["input_wave"] = payload["input_wave"]
        if "mpx_wave" in payload and isinstance(payload["mpx_wave"], list):
            wave_state["mpx_wave"] = payload["mpx_wave"]


def _audio_telemetry_loop() -> None:
    while True:
        if not audio_worker_ready.is_set():
            time.sleep(0.1)
            continue
        with audio_worker_lock:
            telemetry_q = audio_telemetry_queue
        if telemetry_q is None:
            time.sleep(0.1)
            continue
        try:
            payload = telemetry_q.get(timeout=0.5)
        except queue.Empty:
            continue
        except Exception:
            time.sleep(0.1)
            continue
        if isinstance(payload, Mapping):
            _apply_audio_telemetry(payload)


def sig_abort(sig, _frame):
    rds_state["running"] = False
    mpx_state["running"] = False
    _shutdown_audio_worker_process(timeout=0.8)
    save_config()
    os._exit(0)


signal.signal(signal.SIGINT, sig_abort)


def refresh_monitor_snapshot() -> dict[str, Any]:
    with monitor_lock:
        monitor_data["heartbeat"] = int(time.time() * 1000)
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
            "orbass_enabled": bool(mpx_state.get("orbass_enabled")),
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


threading.Thread(target=monitor_pusher_loop, daemon=True).start()
threading.Thread(target=_audio_telemetry_loop, daemon=True).start()
threading.Thread(target=_config_writer_loop, daemon=True).start()


def launch_audio_thread(capture_seconds=None):
    _sync_audio_worker_state()
    return _send_audio_command({"type": "start", "capture_seconds": capture_seconds})


def stop_audio_thread(timeout=1.0):
    mpx_state["running"] = False
    rds_state["running"] = False
    _send_audio_command({"type": "stop", "timeout": timeout})


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
        _sync_audio_worker_state()
        _send_audio_command(
            {
                "type": "restart",
                "reason": reason,
                "capture_seconds": capture_seconds_cli,
            }
        )
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
    allow_subnets[:] = _merge_allow_subnets(parsed_subnets)
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
    with monitor_clients_lock:
        monitor_clients += 1
    join_room(monitor_room)


@socketio.on("disconnect")
def handle_disconnect():
    global monitor_clients
    with monitor_clients_lock:
        monitor_clients = max(0, monitor_clients - 1)


@socketio.on("update")
def handle_update(data):
    if not session.get("auth"):
        return
    prev_mpx_state = dict(mpx_state)
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
            rds_updates = {k: v for k, v in changes.items() if k in rds_state}
            mpx_updates = {k: v for k, v in changes.items() if k in mpx_state}
            orbass_keys = {"orbass_enabled", "orbass_amount", "orbass_freq_hz", "orbass_harmonics"}
            orbass_changed = sorted(set(mpx_updates).intersection(orbass_keys))
            orbass_profile_jump = False
            if orbass_changed:
                amount_jump = False
                freq_jump = False
                harm_jump = False
                try:
                    if "orbass_amount" in mpx_updates:
                        amount_jump = (
                            abs(float(mpx_updates["orbass_amount"]) - float(prev_mpx_state["orbass_amount"]))
                            >= 0.12
                        )
                    if "orbass_freq_hz" in mpx_updates:
                        freq_jump = (
                            abs(float(mpx_updates["orbass_freq_hz"]) - float(prev_mpx_state["orbass_freq_hz"]))
                            >= 8.0
                        )
                    if "orbass_harmonics" in mpx_updates:
                        harm_jump = (
                            abs(
                                float(mpx_updates["orbass_harmonics"])
                                - float(prev_mpx_state["orbass_harmonics"])
                            )
                            >= 0.12
                        )
                except Exception:
                    pass
                orbass_profile_jump = (
                    len(orbass_changed) >= 3
                    or ("orbass_enabled" in orbass_changed and len(orbass_changed) >= 2)
                    or amount_jump
                    or freq_jump
                    or harm_jump
                )
            if rds_updates or mpx_updates:
                _send_audio_command(
                    {
                        "type": "update_state",
                        "rds": rds_updates,
                        "mpx": mpx_updates,
                    }
                )
            if set(changes).intersection(PROCESSING_RESET_KEYS) or orbass_profile_jump:
                dsp_control["reset"] = True
                _send_audio_command({"type": "dsp_reset"})
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
    mp.freeze_support()
    args = parse_cli_args()
    if args.config:
        CONFIG_FILE = args.config
        ensure_config_exists(CONFIG_FILE)
    load_config()
    logger.info("StereoFool v%s starting", APP_VERSION)
    apply_cli_overrides(args)
    log_available_devices()
    normalize_device_indices()
    _start_audio_worker_process()
    _sync_audio_worker_state()
    auto_start_if_enabled()
    try:
        run_web_server()
    finally:
        _shutdown_audio_worker_process(timeout=1.0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
