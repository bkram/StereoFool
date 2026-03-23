# StereoFool Future Roadmap

## Cross-Platform Vision

The goal is to make StereoFool a truly cross-platform FM audio processor that runs on:
- macOS (current)
- Linux
- Windows

## Strategy

### 1. Port MPXGenerator to C++

The DSP core (MPXGenerator) is the "crown jewel" - the real-time FM MPX generation engine.

**Approach:**
- Rewrite MPXGenerator in clean C++ (C++17)
- Use only standard C++ libraries (no platform-specific code)
- Create C API wrapper (extern "C") for language bindings
- Keep same architecture: per-sample processing, filter cascades, RDS coder

**Benefits:**
- Portable to any platform with a C compiler
- Can be called from Swift, Python, Rust, etc.
- JUCE framework integration ready

### 2. Cross-Platform GUI

**Recommended: JUCE**

| Framework | Pros | Cons |
|----------|------|------|
| **JUCE** | Built for audio, VST/AU export, cross-platform native | Less flexible UI |
| **Qt** | Excellent cross-platform, flexible | Larger, more complex |
| **ImGui** | Fast, simple | Not native-looking |

**Recommendation: JUCE**
- Built specifically for audio applications
- Native look on each platform
- Easy integration with C++ DSP code
- Can export as VST3/AU plugins

### 3. Architecture

```
┌─────────────────────────────────────────────┐
│              Cross-Platform UI              │
│              (JUCE on Win/Lin,             │
│               SwiftUI on macOS)            │
└─────────────────┬───────────────────────────┘
                  │ C API
┌─────────────────▼───────────────────────────┐
│           MPXGenerator C++ Core             │
│  - Stereo encoder                           │
│  - RDS coder                                │
│  - DSP processing                           │
│  - All platform-agnostic                    │
└─────────────────────────────────────────────┘
```

### 4. Platform-Specific Audio

- **macOS**: AVAudioEngine (current)
- **Linux**: ALSA or PipeWire + JACK
- **Windows**: WASAPI or ASIO

Each platform has its own audio I/O layer calling into the shared C++ DSP core.

## Implementation Notes

### C++ Core Requirements
- No Swift/Objective-C dependencies
- No platform APIs (CoreAudio, ALSA, WASAPI)
- Thread-safe configuration updates
- Lock-free audio callback interface

### Swift Integration (macOS)
- Keep current SwiftUI app
- Use C bridging header to call C++ core
- Gradually migrate DSP to C++

### Performance Target
- Maintain real-time performance on mid-range hardware
- i7-7700K / Ryzen 5 2600 equivalent or better
- < 10% CPU with full processing chain

## Current Status

- ✅ macOS/SwiftUI version in active development
- ✅ Current macOS chain now includes a dedicated final MPX loudness stage, limiter telemetry, mono bass, and improved stereo-image handling
- ⏳ C++ core - not started
- ⏳ JUCE GUI - not started
- ⏳ Linux/Windows ports - not started

## Near-Term Priorities Before Cross-Platform Work

- finish the oversampled composite limiter/clipper path so the FM back end is more intentional
- add deterministic MPX verification and stereo/mono-compatibility checks
- tighten pilot/RDS/deviation calibration workflow
- stabilize presets for Orbass, widener, mono bass, and final-stage loudness
