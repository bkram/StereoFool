## Orbass TODO

- Document the current `orbass` configuration from `StereoFool.ini`:
  - `orbass_enabled = True`
  - `orbass_amount = 0.339336`
  - `orbass_freq_hz = 131.11`
- Confirm whether `131.11 Hz` is still the intended target frequency for the current processing preset.
- Decide whether `orbass_amount = 0.339336` should remain as a tuned value or be rounded to a cleaner default for maintainability.
- If this is a reference preset, add a short explanation of the intended audible result and the source material it was tuned against.

## Performance TODO

- Replace the `NSLock`-based input ring buffer with a lock-free single-producer/single-consumer design, or at minimum reduce lock hold time in [`StereoInputRingBuffer.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/StereoInputRingBuffer.swift#L16). The current read and write paths lock on every audio block and can block the realtime render thread.
- Remove per-callback heap allocations in [`AudioOutputEngine.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/AudioOutputEngine.swift#L502). The `int16`, `int32`, and interleaved fallback capture paths allocate fresh `left` and `right` arrays every callback instead of reusing the preallocated conversion buffers.
- Cache FFT setup, windowing data, and scratch buffers for the MPX spectrum path in [`SwiftUIControlApp.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/SwiftUIControlApp.swift#L1585). `computeMPXSpectrum` currently rebuilds the Hann window, FFT setup, and multiple arrays on each refresh.
- Move RDS wall-clock and string-to-byte preparation off the audio render path in [`MPXGenerator.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/MPXGenerator.swift#L1198). Group generation still does `Date`/`Calendar` work and repeated UTF-8 array conversion during sample generation.
- Review scope and signal snapshot allocation churn in [`AudioOutputEngine.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/AudioOutputEngine.swift#L964) and [`SwiftUIControlApp.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/SwiftUIControlApp.swift#L1557). These are lower priority than the audio-thread issues but still create avoidable UI-side work.
