# macOS TODO

## DSP / MPX

- Turn the current filtered internal oversampling path in [`MPXGenerator.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/MPXGenerator.swift) into a clearly intentional composite limiter/clipper design with one coherent oversampling implementation.
- Add deterministic MPX verification for:
  - final-stage loudness behavior
  - full-MPX safety limiter engagement
  - pilot/RDS integrity
  - mono-compatibility and stereo-image behavior
- Add stereo-image metering or correlation indication so widener and mono-bass tuning are not done blind.
- Validate Orbass, mono bass, widener, and multiband interaction on difficult real program material and tighten presets accordingly.

## Performance

- Replace the `NSLock`-based input ring buffer with a lock-free single-producer/single-consumer design, or at minimum reduce lock hold time in [`StereoInputRingBuffer.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/StereoInputRingBuffer.swift#L16). The current read and write paths lock on every audio block and can block the real-time render thread.
- Remove per-callback heap allocations in [`AudioOutputEngine.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/AudioOutputEngine.swift#L502). The `int16`, `int32`, and interleaved fallback capture paths allocate fresh `left` and `right` arrays every callback instead of reusing the preallocated conversion buffers.
- Cache FFT setup, windowing data, and scratch buffers for the MPX spectrum path in [`SwiftUIControlApp.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/SwiftUIControlApp.swift#L1585). `computeMPXSpectrum` currently rebuilds the Hann window, FFT setup, and multiple arrays on each refresh.
- Move RDS wall-clock and string-to-byte preparation off the audio render path in [`MPXGenerator.swift`](/Users/mrk/Projects/git/StereoFool/macOS/Sources/StereoFool/MPXGenerator.swift#L1198). Group generation still does `Date`/`Calendar` work and repeated UTF-8 array conversion during sample generation.

## UX / Release

- Add widener/image presets such as `Safe FM`, `Open Music`, and `Wide CHR`.
- Add clearer calibration UI for pilot %, RDS %, audio-composite peak, and composite headroom instead of relying only on status text.
- Run a release smoke pass for `0.85` and trim any defaults that still need manual correction after the recent DSP changes.
