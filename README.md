# StereoFool

Version: 0.6

StereoFool is a Python app that generates an FM composite MPX signal with RDS and serves a
browser-based control panel. It synthesizes pilot/RDS, muxes stereo audio sources, and sends
the resulting MPX to a local audio output device. In 0.6, the audio engine runs in a dedicated
worker process separate from the web UI process.

The name StereoFool is a pun on the great commercial tool StereoTool.

This is an _experimental project and not suitable for professional or production use_. The RDS
backend and Web UI code is based on the
[rds-master project from RyanG](https://github.com/ryanginn/rds-master), and much of the
codebase is AI-generated.
StereoFool targets core RDS behavior from EN 50067 / IEC 62106, but it is not certified or
guaranteed compliant, and no warranty is implied.

## Interface overview

The UI uses a single, unified navigation structure with sections aligned to a broadcast workflow:

- System
- Interfaces
- Processing
- Levels
- RDS
- RDS Advanced
- Monitoring
- Settings

## Features

- Audio engine and web server process isolation (separate worker + IPC state/telemetry)
- Real-time MPX generation with pilot, stereo sum/diff, and optional RDS subcarrier
- RDS encoder with PS/RT/PTY/CT/AF and optional RT+ support
- RDS subcarrier phase-locked to the pilot with EN 50067 biphase shaping (experimental)
- Optional EN 50067-style RDS group scheduling preset (overrides manual sequence)
- Input audio from sound device or test tone
- Input gain plus optional audio-domain processing: wideband AGC, HPF, LPF, HF trim, pilot notch
- Orbass low enhancer (with profile presets)
- Multiband compressor (3-band or 5-band) with configurable knee, link, and program-dependent release
- Optional stereo widener (width/center/mix)
- Pre-emphasis (50/75 us), optional pre-emphasis HF control, optional pre-emphasis limiter
- Optional lookahead limiting and composite clipping for MPX protection
- MPX cleanup controls: audio-MPX LPF, MPX DC block, optional notch
- Web UI (Flask + Socket.IO) for live control, scopes, and monitoring
- Monitor meter sticky-peak mode (hold/fall/reset in UI)
- Persisted settings in `stereofool.ini`

## Compatibility

- Tested on macOS and Windows.
- On macOS, confirm the audio interface is set to 192 kHz in "Audio MIDI Setup".
- On Windows, set the audio device sample rate to 192 kHz in the OS sound settings.
- It likely works on Linux, but this has not been verified.

## Requirements

- Python 3.10+
- PortAudio-compatible audio backend (Core Audio/ALSA/PulseAudio/JACK)
- Packages in `requirements.txt`
- Flask-SocketIO runs in `threading` mode in this project (no gevent/eventlet dependency)
- A 192 kHz-capable audio interface for MPX output
- Input devices can be 48 kHz (the app handles conversion)
- For experimentation, use a virtual audio loopback so another app can feed StereoFool (e.g., BlackHole on macOS, VB-Audio Virtual Cable on Windows).

## Quick start

Assumes Python and `pip` are installed.

### macOS/Linux:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python stereofool/app.py
```

### Windows (PowerShell):

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python stereofool/app.py
```

### Windows: Use `spatialaudio/portaudio-binaries`

If the default PortAudio bundled with your Python/sounddevice install has host-API issues
(for example WASAPI or WDM-KS behavior), you can test an alternate PortAudio DLL build.

1. Download a Windows release asset from
   [spatialaudio/portaudio-binaries](https://github.com/spatialaudio/portaudio-binaries/releases).
2. Extract it and copy the DLL you want to test into a local folder, for example:
   `.\third_party\portaudio\portaudio.dll`
3. In PowerShell, prepend that folder to `PATH` before starting Python:

```powershell
$env:PATH = "$PWD\third_party\portaudio;$env:PATH"
python -c "import sounddevice as sd; print(sd.get_portaudio_version()); print([a['name'] for a in sd.query_hostapis()])"
python stereofool/app.py
```

Notes:
- Run StereoFool from the same shell session where `PATH` was updated.
- This method is non-destructive; remove that `PATH` override to return to the default DLL.
- Use `STEREOFOOL_HOSTAPI` to restrict backend selection during testing (example: `wasapi`, `wdmks`, `directsound`, `mme`).

On Windows, on low-end systems, higher priority may improve stability:

```cmd
start "" /HIGH python stereofool/app.py
```

Open `http://localhost:8300`.

Default login (if not overridden in `stereofool.ini` or Settings):
- Username: `admin`
- Password: `pass`

## Runtime architecture

- The Flask web app process handles login, UI routes, and Socket.IO transport.
- A dedicated audio worker process runs the DSP/audio callbacks.
- State changes are sent from web to worker via command queue; meter/wave/monitor telemetry is sent back via telemetry queue.
- This separation reduces UI reload/request impact on audio continuity versus the older single-process design.

## Configuration

Settings are stored in `stereofool.ini` and loaded on startup. The UI updates settings live and
writes back to the config file.

You can point to a different config file with `--config` (a new file will be created if it does not exist):

```bash
python stereofool/app.py --config custom.ini
```

Config sections:

- `SYSTEM`: server settings (e.g., `port`)
- `SYSTEM` also supports `allow_subnets` (comma-separated CIDR list). Custom entries are additive; localhost (127.0.0.0/8, ::1/128) is always allowed.
- `INTERFACES`: device indices, source mode, monitor settings, block size, and audio priority profile
- `MPX`: MPX processing and levels
- `RDS`: program data and RDS settings
- `AUTH`: username and hashed password

Key environment variables:

- `STEREOFOOL_SECRET`: override the Flask session secret
- `STEREOFOOL_HOSTAPI`: comma-separated host API filter (e.g. `wasapi`, `wdmks`, `Core Audio`, `ALSA`)

### Buffering and Web Reload Behavior

- `INTERFACES.blocksize` controls audio callback buffer size. You can also set this from the
  Interfaces pane (`Audio Engine > Block Size`).
- Larger block sizes reduce CPU pressure and dropouts, but increase latency.
- Smaller block sizes reduce latency, but are more sensitive to CPU contention.
- Suggested starting points:
  - fast systems: `2048` or `4096`
  - older/slower systems: `8192` or `16384`
- `INTERFACES.audio_priority_profile` (`normal`, `high`, `realtime-attempt`) can improve stability on busy systems.

The web UI and audio engine are process-isolated in 0.6, so browser reload traffic usually has
less direct impact on audio. Under heavy OS-level CPU or driver contention, brief glitches can
still occur; increase block size and/or priority profile when needed.

## Knowledge sources and references

Implementation notes and standards references live under `documents/`. External sources used in
this project and docs:

- EN 50067 and IEC 62106 parts for RDS
- ITU-R BS.450-4 for FM stereo MPX characteristics
- RadioText Plus overview (RT+)
- PortAudio Windows binaries (for host-API troubleshooting): https://github.com/spatialaudio/portaudio-binaries
- SimpleMultiBandComp reference (historical compressor inspiration): https://github.com/matkatmusic/SimpleMultiBandComp
- Airwindows Wider reference (historical widener inspiration): https://github.com/airwindows/airwindows

## RDS/MPX notes

- RDS carrier frequency is config-only; the UI exposes carrier level and program data.
- The standards schedule toggle applies EN 50067-style repetition rates; LPS is non-standard.
- Composite deviation and pilot level are not calibrated; verify levels before on-air use.
- Current multiband and widener implementations are integrated in-project DSP blocks.

## Calibration (WAV workflow)

Use the built-in WAV capture and analyzer to set pilot and RDS deviation targets.

1. Set `source_mode = input` or `test_tone` (mono recommended for calibration).
2. Start a short capture:

```bash
python stereofool/app.py --save-file output.wav --length 5
python tools/analyze_mpx.py output.wav
```

3. Adjust:
   - `mpx_deviation_khz` and/or gains until composite peak is ~75 kHz.
   - `pilot_level` until pilot peak is ~5.5 kHz (8-10% of 75 kHz).
   - `rds_level` until RDS band peak is ~2.0 kHz.
4. Re-capture and repeat until the analyzer reports the targets.

## Offline MPX matrix test

Run the offline MPX/RDS combination test without audio hardware:

```bash
python tools/mpx_matrix_test.py --config stereofool.ini
```

The report is written to `captures/matrix_report.jsonl`.

## Development

Formatting and type checks:

```bash
ruff format .
ruff check .
pyright
```

## Notes

- Audio device indexes are from `sounddevice` and vary by system.
- RDS/MPX runs in real-time; CPU use depends on sample rate and effects.

## License

GPL-3.0. See `LICENSE`.
