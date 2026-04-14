# Architecture

## Overview

MPX Prime is a native macOS audio application built with Swift and SwiftUI. It provides real-time FM stereo MPX generation with RDS support using AVAudioEngine.

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
│    └── Multiband compressor with complementary LR4 crossovers (optional)
│
├──► Pre-emphasis stage (region specific)
│    ├── Pre-emphasis 50 µs / 75 µs
│    └── Optional pre-emphasis HF control
│
├──► Pre-encode audio limiter (L/R domain, stereo-linked)
│    └── True-peak limiter on L/R after pre-emphasis, before stereo encoding
│        Controls peaks before they enter the stereo encoder where
│        pre-emphasis would amplify them further
│
├──► Stereo encoder (phase-coherent)
│    ├── M = (L+R)/2  → steep LPF ~15.0–15.2 kHz
│    ├── S = (L−R)/2  → steep LPF ~15.0–15.2 kHz
│    └── DSB-SC: S × cos(2π·38 kHz)   where 38 kHz = 2×pilot (phase locked)
│
├──► RDS path (parallel, MPX domain @ output rate)
│    ├── RDS baseband (biphase / shaping)
│    ├── Gaussian filter (spectral containment)
│    └── 57 kHz subcarrier (3×pilot, phase locked)
│
├──► Final MPX chain (audio composite only)
│    ├── Final Drive (audio-composite domain)
│    ├── Audio-composite limiter (4× oversampled true-peak with decimation LP)
│    ├── MPX output calibration
│    └── Safety limiter (audio composite only — no pilot, no RDS)
│
├──► Post-limiter subcarrier injection
│    ├── Pilot 19 kHz (≈8–10% injection, constant amplitude)
│    ├── RDS 57 kHz (≈3–7% injection, constant amplitude)
│    └── Subcarriers bypass all limiting stages to preserve constant
│        amplitude for reliable stereo decoding and RDS reception
│        (professional broadcast standard: Omnia, Orban, Stereotool)
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

Within the main audio path, MPX Prime currently runs:

1. Input trim and conditioning
2. Wideband AGC
3. HF trim
4. Orbass
5. Mono bass
6. Stereo widener
7. Multiband with 3-band or 5-band complementary crossovers
8. Stereo-image protection
9. Pre-emphasis
10. Pre-encode audio limiter (L/R domain, stereo-linked true-peak)
11. Stereo encoder (M/S encoding, 38 kHz DSB-SC subcarrier)
12. Audio-composite limiter (4× oversampled true-peak)
13. Safety limiter (audio composite only)
14. Pilot and RDS injection (post-limiter, constant amplitude)

When `Mono Mode` is enabled, MPX Prime suppresses the pilot, stereo subcarrier, and RDS injection so the transmitted composite is true mono.

## External Dependencies

- AVFoundation / CoreAudio for audio I/O
- Accelerate framework for vDSP (SIMD-optimized metering)
- SwiftUI for native macOS UI

## Current DSP notes

- Orbass is now intentionally conservative. It uses adaptive low-band enhancement with restrained harmonic and optional subharmonic support, plus gated makeup behavior to reduce bass pumping and low-level artifacts.
- The multiband stage now uses complementary Linkwitz-Riley 4th-order stereo crossover stages instead of one-pole residual band splits. This is a significant improvement in band separation and should reduce recombination smear and tonal instability when adjacent bands compress differently.
- The final MPX chain remains verification-backed. Structural cleanup there is intentionally done in small steps because even behavior-preserving refactors can change composite output measurably.
- Verification now covers both composite safety and decoded-audio quality signals. In addition to the base offline verifier, a focused preset sweep exists for the main 5-band preset family (`5B AC/Pop`, `5B CHR/EDM`, `5B Rock`, `5B Talk`, `5B News`, `5B Urban`, `5B Dance`).
