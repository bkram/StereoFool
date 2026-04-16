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
├──► Phase rotation (optional)
│    └── 4-pole allpass chain at ~200 Hz — reduces waveform asymmetry
│        by 3–4 dB, yielding free headroom for downstream stages
│
├──► Input conditioning (audio domain)
│    ├── Wideband AGC (optional)
│    ├── High-pass ~20–30 Hz (infrasonic removal)
│    ├── 15 kHz low-pass
│    └── HF trim shelf (optional)
│
├──► Tonal shaping (audio domain)
│    └── 4-band parametric EQ (optional)
│        Low shelf + 2 peaking + high shelf, placed before dynamics
│
├──► Dynamics and image shaping (audio domain, float)
│    ├── Orbass bass enhancement (optional)
│    ├── Mono bass management (optional)
│    ├── Stereo widener with image protection (optional)
│    └── Multiband compressor with complementary LR4 crossovers (optional)
│        ├── Per-band downward expander (optional noise reduction)
│        └── Per-band fast peak limiter (optional transient control)
│
├──► Peak control (audio domain, L/R)
│    ├── Bass clipper (optional) — dedicated LF clipper with LR4 split
│    │   reduces bass-induced IMD in downstream stages
│    └── Distortion-cancelled clipper (optional) — Orban-principle LF
│        distortion cancellation: clip, extract LF error, subtract
│
├──► Encoder HF guard
│    └── Dynamic HF reduction to protect pre-emphasis compliance
│
├──► Encoder program lowpass (~15 kHz)
│    └── Final audio-bandwidth guard; stops later nonlinear stages from
│        re-broadening the transmitted audio spectrum
│
├──► Stereo-image protection
│    └── Limits side-channel expansion from Orbass/widener
│
├──► Pre-emphasis (L/R domain, region specific)
│    ├── 50 us (Region 1) or 75 us (Region 2)
│    └── Applied in L/R domain before the pre-encode limiter so the
│        limiter can peak-control the 10-12 dB HF boost
│
├──► Pre-encode audio limiter (L/R domain, stereo-linked)
│    └── True-peak limiter on pre-emphasized L/R before stereo encoding
│
├──► Stereo encoder (phase-coherent)
│    ├── M = (L+R)/2
│    ├── S = (L-R)/2
│    └── DSB-SC: S x cos(2pi*38 kHz)   where 38 kHz = 2xpilot (phase locked)
│
├──► RDS path (parallel, MPX domain @ output rate)
│    ├── RDS baseband (biphase / shaping)
│    ├── Gaussian filter (spectral containment)
│    └── 57 kHz subcarrier (3xpilot, phase locked)
│
├──► Final MPX chain (audio composite only)
│    ├── Final Drive (audio-composite domain)
│    ├── Audio-composite limiter (4x oversampled true-peak with decimation LP)
│    ├── BS.412 MPX power limiter (optional, EU regulatory compliance)
│    │   Rolling 60-second average power measurement with slow gain reduction
│    ├── MPX output calibration
│    └── Safety limiter (audio composite only — no pilot, no RDS)
│
├──► Post-limiter subcarrier injection
│    ├── Pilot 19 kHz (approx 8–10% injection, constant amplitude)
│    ├── RDS 57 kHz (approx 3–7% injection, constant amplitude)
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

Within the main audio path, MPX Prime runs:

1. Input gain and mono fold
2. **Phase rotation** (4-pole allpass, optional)
3. Wideband AGC
4. Input HPF
5. Program lowpass
6. HF trim
7. **Parametric EQ** (4-band: low shelf + 2 peaking + high shelf, optional)
8. Orbass
9. Mono bass + stereo widener
10. Multiband compressor (3-band or 5-band LR4 crossovers)
    - **Per-band downward expander** (optional, within multiband)
    - **Per-band fast peak limiter** (optional, within multiband)
11. **Bass clipper** (dedicated LF clipper with LR4 split, optional)
12. **Distortion-cancelled clipper** (Orban-principle LF cancellation, optional)
13. Encoder HF guard
14. Encoder program lowpass (~15 kHz final audio-bandwidth guard)
15. 19 kHz pilot-protection notch (Q=50, active when pre-emphasis > 0)
16. Stereo-image protection
17. Pre-emphasis (L/R domain, 50/75 µs)
18. Pre-encode audio limiter (L/R domain, stereo-linked true-peak, on pre-emphasized signal)
19. Stereo encoder (M/S encoding, 38 kHz DSB-SC subcarrier)
20. Audio-composite limiter (4x oversampled true-peak)
21. **Composite clipper** (8x oversampled tanh soft-clip, optional, primary loudness lever)
22. **BS.412 MPX power limiter** (60s rolling average, optional, EU compliance)
23. Safety limiter (audio composite only)
24. Pilot and RDS injection (post-limiter, constant amplitude)

Stages in **bold** are new additions. All new stages are disabled by default and can be enabled via config/UI.

When `Mono Mode` is enabled, MPX Prime suppresses the pilot, stereo subcarrier, and RDS injection so the transmitted composite is true mono.

## External Dependencies

- AVFoundation / CoreAudio for audio I/O
- Accelerate framework for vDSP (SIMD-optimized metering)
- SwiftUI for native macOS UI

## DSP Stage Details

### Phase Rotator
4-pole cascaded second-order allpass filters at configurable frequency (default 200 Hz). Reduces waveform asymmetry (especially male voice) by 3-4 dB, providing free headroom for downstream AGC, compressors, and limiters. Standard in Orban Optimod, Stereotool, and BreakawayOne.

### Parametric EQ
4-band EQ placed before dynamics processing: band 1 (low shelf), bands 2-3 (peaking), band 4 (high shelf). All bands expose frequency and gain (+/-12 dB). Q is exposed only for the peaking bands; the shelves use an RBJ slope=1.0 (Butterworth) shape. Provides tonal shaping that feeds into the multiband crossover splitting.

### Multiband Limiter
Per-band fast peak limiters operating after multiband compression and before band summation. Fast attack, high ratio brick-wall limiting controls instantaneous transient peaks independently from the compressor's ratio-based dynamics. Prevents transient leakage without forcing the compressor to be overly aggressive.

### Downward Expander
Per-band noise reduction within the multiband compressor stage. Threshold-based gain reduction on quiet bands prevents AGC from lifting the noise floor during quiet passages.

### Bass Clipper
Dedicated clipper for low-frequency content using LR4 crossover to split, tanh-clip the low band, and recombine. Pre-clipping bass peaks independently before the final stages dramatically reduces bass-induced intermodulation distortion. Used by Omnia, Breakaway, and Stereotool.

### Distortion-Cancelled Clipper
L/R domain audio clipper implementing Orban's distortion-cancellation principle: clip the signal, extract the error (clipped minus original), lowpass-filter the error below a configurable cancellation frequency (~2 kHz), and subtract it from the clipped signal. This cancels low-frequency distortion products while leaving only high-frequency distortion that is psychoacoustically masked by the signal. The error path uses a Linkwitz-Riley 4th-order LP (two cascaded 2nd-order Butterworth sections at Q=0.707), giving a 24 dB/oct rolloff with -6 dB at the cancellation cutoff.

### BS.412 MPX Power Limiter
ITU-R BS.412 rolling average power measurement with slow gain reduction for European regulatory compliance (required in DE, AT, CH, SE, CZ, SI, and others). Measures decimated RMS power over a configurable sliding window (default 60 seconds) and applies slow gain reduction when average power exceeds the threshold. Operates on the audio composite before the safety limiter.

## General DSP notes

- Orbass is intentionally conservative. It uses adaptive low-band enhancement with restrained harmonic and optional subharmonic support, plus gated makeup behavior to reduce bass pumping and low-level artifacts.
- The multiband stage uses complementary Linkwitz-Riley 4th-order stereo crossover stages. This provides clean band separation and reduces recombination smear and tonal instability when adjacent bands compress differently.
- The final MPX chain remains verification-backed. Structural cleanup there is intentionally done in small steps because even behavior-preserving refactors can change composite output measurably.
- Verification covers both composite safety and decoded-audio quality signals. In addition to the base offline verifier, a focused preset sweep exists for the main 5-band preset family (`5B AC/Pop`, `5B CHR/EDM`, `5B Rock`, `5B Talk`, `5B News`, `5B Urban`, `5B Dance`).
- All new DSP stages (phase rotator, parametric EQ, multiband limiter, downward expander, bass clipper, distortion-cancelled clipper, BS.412) are disabled by default and have zero impact on the signal chain until enabled. All support live-apply via RuntimeConfig.
