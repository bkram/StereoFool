# Architecture

## Overview

StereoFool is a single-process Python application that combines a web control plane with a real-time audio engine. The Flask app serves an inline HTML UI with a single, unified navigation structure and uses Socket.IO to push updates to the running audio pipeline. Standards references and implementation notes live under `documents/`.

```
Browser UI  <->  Flask + Socket.IO  <->  State (mpx_state, rds_state)
                                             |
                                             v
                                      Audio Engine
                                      (sounddevice)
```

```txt
BLOCK DIAGRAM (revised, includes all refinements)

Audio input (L/R) @ interface rate (typically 192 kHz output, optional 48 kHz processing)
│
├──► Input conditioning (audio domain)
│    ├── High-pass ~20–30 Hz (infrasonic removal)
│    ├── 15 kHz low-pass
│    ├── HF trim shelf (optional)
│    └── 19 kHz pilot notch
│
├──► Dynamics (audio domain, float)
│    ├── Multiband compressor (SimpleMultiBandComp split + JUCE-style compressor)
│    └── Airwindows Wider-style stereo widener (optional)
│
├──► Pre-emphasis stage (region specific)
│    ├── Pre-emphasis 50 µs / 75 µs
│    └── Optional pre-emphasis HF control
│
├──► Stereo encoder (phase-coherent)
│    ├── M = (L+R)/2  → steep LPF ~15.0–15.2 kHz (linear-phase FIR, not “true brickwall”)
│    ├── S = (L−R)/2  → steep LPF ~15.0–15.2 kHz (linear-phase FIR)
│    ├── Pilot 19 kHz (≈8–10% injection, exact phase reference)
│    └── DSB-SC: S × cos(2π·38 kHz)   where 38 kHz = 2×pilot (phase locked)
│
├──► Resample to MPX rate (if processing at 48 kHz)
│    └── Upsample 48 kHz → output rate (polyphase FIR)
│
├──► RDS path (MPX domain @ 192 kHz)
│    ├── RDS baseband (biphase / shaping)
│    ├── Gaussian filter (spectral containment)
│    └── 57 kHz subcarrier (3×pilot, phase locked), injection ~3–7% (often 4–6%)
│
├──► Composite sum (phase-coherent @ 192 kHz)
│    └── MPX = M + (S@38k DSB-SC) + Pilot19 + RDS57
│       (coherence: 19×2=38, 19×3=57; maintain pilot phase through chain)
│
├──► Composite cleanup (MPX domain)
│    ├── Very-low HPF ~2 Hz (removes composite DC/bias)
│    └── Optional notch (if enabled)
│
├──► Composite protection (MPX-aware, OVERSAMPLED)
│    ├── Composite limiter/clipper (captures overshoot, minimizes splatter)
│    └── Constraints: preserve pilot phase; avoid phase-warping nonlinearities
│
├──► Calibration / scaling
│    └── Set reference: 0 dBFS = ±75 kHz deviation (or your target)
│       Notes: 100% modulation = ±75 kHz; pilot typically ≈8–10% of total deviation
│
└──► Output formatting
     ├── Output: PCM to DAC (PortAudio), typical 192 kHz
     └── Monitor output (optional): demod → L/R (de-emphasis, resample)

```

## Major components

- `stereofool/app.py`: Web server, config load/save, and thread orchestration.
- `stereofool/audio.py`: Real-time MPX audio/DSP pipeline and monitoring metrics.
- `stereofool/rds.py`: RDS group scheduling, bitstream generation, and subcarrier shaping.
- `documents/`: Reference PDFs used to guide RDS/MPX behavior and compliance notes.
- Web UI: Inline HTML template rendered by Flask with a unified section sidebar. JavaScript emits `update` and `control` events over Socket.IO.
- State/config: `rds_state` and `mpx_state` store runtime settings; `stereofool.ini` persists them via `configparser`.
- Audio I/O: `sounddevice` streams audio to/from selected devices with a configurable sample rate and buffer size.
- RDS encoder: Builds RDS groups, schedules group sequences (manual, auto, or standards preset), and generates a biphase-shaped subcarrier at `rds_freq` locked to the pilot phase.
- MPX generator: Mixes stereo sum/diff, pilot, optional test tone, and optional RDS into a composite MPX signal.

## DSP chain (high level)

- Input gain, low-cut, HF trim, and 15 kHz low-pass + 19 kHz notch on baseband audio.
- Multiband compression (SimpleMultiBandComp split + JUCE-style compressor).
- Optional stereo widener (Airwindows Wider).
- Pre-emphasis + optional HF control.
- Stereo sum/diff + 38 kHz DSB-SC subcarrier generation.
- Pilot and RDS subcarrier injection (RDS uses EN 50067 biphase shaping + Gaussian filter).
- Optional lookahead MPX limiter.
- MPX DC block and optional notch.
- Output gain before the soundcard.

## Data flow

1. User updates settings in the unified UI; Socket.IO sends updates to the server.
2. Server updates `rds_state` and `mpx_state` and writes to `stereofool.ini`.
3. The audio thread reads state and generates the MPX buffer each callback.
4. Monitoring data (PS/RT/PTY/AF/PI, etc.) streams back to the UI via Socket.IO.

## Threading model

- Flask runs in the main thread.
- Audio processing runs in background threads managed by `sounddevice` and custom worker threads.
- RDS scheduling and UI monitor updates are coordinated through shared state dictionaries.

## External dependencies

- `sounddevice` for PortAudio I/O
- `numpy`/`scipy` for DSP
- `flask` and `flask-socketio` for the web control interface
