# Clipper aliasing baseline (pre-Phase 7.1)

Captured on the unrefactored code so post-7.1 deltas are attributable.

| Clipper | Test | Measured alias energy | Threshold | Delta to threshold |
|---|---|---|---|---|
| `DistortionCancelledClipper` | 5111 Hz @ 48 kHz, amp 0.95, ceiling -3 dB, cancelFreq 2 kHz, sum of 5 alias bins {22445, 17334, 12223, 7112, 2000} Hz | **-28.731249 dBFS** | -75 dBFS | +46.27 dB over |
| `BassClipper` | 113 Hz @ 48 kHz, amp 0.95, crossover 150 Hz, threshold -3 dB, drive 1.5, sum across alias bins above 1 kHz (spacing 113 Hz, offset -25 Hz from real harmonic ladder) | **-56.50266 dBFS** | -75 dBFS | +18.50 dB over |

Repeatability: both measurements are bit-identical across three consecutive runs of `swift test`.

## Interpretation

- The DC clipper shows ~46 dB of excess aliasing. This is the dominant HF-aliasing contributor when the stage is enabled; `tanh` harmonics of the 5111 Hz test tone well above Nyquist fold back and land in-band with very little attenuation (the clipper's LP-filtered error cancellation does not address them).
- The bass clipper shows ~18 dB of excess aliasing. The smaller magnitude reflects the lower fundamental: tanh harmonics of an 80–113 Hz tone drop roughly as `1/n`, so by the time they reach Nyquist at the 300th-plus harmonic their amplitudes are already -45 to -55 dB below the fundamental. Aliasing is real but less dominant than for the DC clipper.

Both stages should show these alias energies drop well below -75 dBFS once 7.1 wraps them in oversampling with proper reconstruction filtering.

## How to reproduce

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path macOS --filter "aliasing"
```

The failure output prints the measured dBFS. Use the same commands post-refactor to confirm the drop.
