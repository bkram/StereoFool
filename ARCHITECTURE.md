# Architecture

## Overview

StereoFool is a native macOS audio application built with Swift and SwiftUI. It provides real-time FM stereo MPX generation with RDS support using AVAudioEngine.

```
SwiftUI UI  <->  App State (ObservableObject)
                        |
                        v
                 Audio Engine
                 (AVAudioEngine)
```

## Block Diagram

```
Audio Input (L/R) @ interface rate (typically 192 kHz)
│
├──► Input conditioning (audio domain)
│    ├── High-pass ~20–30 Hz (infrasonic removal)
│    ├── 15 kHz low-pass
│    └── HF trim shelf (optional)
│
├──► Dynamics and image shaping (audio domain, float)
│    ├── Wideband AGC (optional)
│    ├── Orbass bass enhancement (optional)
│    ├── Mono bass management (optional)
│    ├── Stereo widener with image protection (optional)
│    └── Multiband compressor (optional)
│
├──► Pre-emphasis stage (region specific)
│    ├── Pre-emphasis 50 µs / 75 µs
│    └── Optional pre-emphasis HF control
│
├──► Stereo encoder (phase-coherent)
│    ├── M = (L+R)/2  → steep LPF ~15.0–15.2 kHz
│    ├── S = (L−R)/2  → steep LPF ~15.0–15.2 kHz
│    ├── Pilot 19 kHz (≈8–10% injection, exact phase reference)
│    └── DSB-SC: S × cos(2π·38 kHz)   where 38 kHz = 2×pilot (phase locked)
│
├──► RDS path (MPX domain @ output rate)
│    ├── RDS baseband (biphase / shaping)
│    ├── Gaussian filter (spectral containment)
│    └── 57 kHz subcarrier (3×pilot, phase locked), injection ~3–7%
│
├──► Composite sum (phase-coherent)
│    └── MPX = M + (S@38k DSB-SC) + Pilot19 + RDS57
│
├──► Final MPX chain
│    ├── Final Drive (audio-composite domain)
│    ├── Audio-composite limiter/clipper
│    ├── MPX output calibration
│    └── Full-MPX safety limiter
│
├──► Output formatting
│    └── Output: PCM to DAC via AVAudioEngine
│
└──► Monitor path (optional)
     └── Demodulated L/R for headphone monitoring
```

## Major Components

- `main.swift`: CLI entry point, config loading, audio engine lifecycle.
- `AudioOutputEngine.swift`: AVAudioEngine setup, render callback, input tap.
- `MPXGenerator.swift`: Real-time MPX/DSP generation, RDS encoding.
- `AppConfig.swift`: Configuration model, INI parsing/serialization.
- `SwiftUIControlApp.swift`: SwiftUI views, state management.
- `AudioDevices.swift`: CoreAudio device enumeration.
- `INIParser.swift`: INI file read/write.

## Threading Model

- Main thread: SwiftUI UI, user interaction
- Audio render callback: Real-time thread (no locks, no allocations)
- Background metering: DispatchQueue with `.userInteractive` QoS for scope/meter updates

## Current processing order

Within the main audio path, StereoFool currently runs:

1. Input trim and conditioning
2. Wideband AGC
3. HF trim
4. Orbass
5. Mono bass
6. Stereo widener
7. Multiband
8. Stereo-image protection
9. Pre-emphasis
10. Stereo coder
11. Pilot and RDS injection
12. Final MPX loudness and safety stages

When `Mono Mode` is enabled, StereoFool suppresses the pilot, stereo subcarrier, and RDS injection so the transmitted composite is true mono.

## External Dependencies

- AVFoundation / CoreAudio for audio I/O
- Accelerate framework for vDSP (SIMD-optimized metering)
- SwiftUI for native macOS UI
