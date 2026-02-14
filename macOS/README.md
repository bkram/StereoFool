# StereoFool Native macOS Prototype

Native macOS audio prototype in Swift.

## Scope (v0)

- realtime output via `AVAudioEngine` + `AVAudioSourceNode`
- realtime input capture via `AVAudioEngine` input tap + ring buffer feeding output callback
- dedicated macOS config file: `macOS/StereoFool.ini`
- MPX tone-path DSP blocks:
  - input gain
  - optional wideband AGC
  - optional Orbass-style bass enhancement
  - optional 3-band dynamics
  - optional stereo widener
  - stereo sum/diff encoder
  - optional mono mode
  - pre-emphasis (0/50/75 us)
  - 19 kHz pilot
  - 38 kHz stereo subcarrier
  - optional RDS (0A/2A plus 3A/10A/11A/15A support)
  - deviation scaling
  - soft clip safety limiter
  - output gain + final clip

## Build

```bash
swift build --package-path macOS
```

## Run

From repo root:

```bash
swift run --package-path macOS StereoFool
```

Run for a fixed time:

```bash
swift run --package-path macOS StereoFool --seconds 10
```

Run with native SwiftUI GUI (sidebar navigation, toolbar transport, monitoring dashboard):

```bash
swift run --package-path macOS StereoFool --gui
```

Run headless:

```bash
swift run --package-path macOS StereoFool --nogui
```

Use a custom config file if needed:

```bash
swift run --package-path macOS StereoFool --config /path/to/your-macos.ini
```

## Release DMG

Build a `.app` bundle and installable `.dmg`:

```bash
./macOS/scripts/make-release-dmg.sh --version 0.1.0
```

Artifacts are written to `macOS/dist/` by default.

GUI device/source selections are persisted to the active config file using:
- `INTERFACES.input_device_uid`
- `INTERFACES.output_device_uid`
- `INTERFACES.monitor_device_uid`
- `INTERFACES.source_mode`
- `INTERFACES.monitor_enabled`

MPX note:
- For stereo MPX, output sample rate must be high enough for 19 kHz pilot + 38 kHz DSBSC (typically 192 kHz hardware rate recommended).
- `Monitor Mode = off` is required for MPX output. `Monitor Mode = on` outputs listen audio, not MPX baseband.

Additional DSP keys in `MPX` (all optional):
- `processing_rate_hz`, `hpf_hz`, `hf_trim_db`, `hf_trim_hz`
- `wideband_agc_enabled`, `wideband_agc_target_db`, `wideband_agc_attack_ms`, `wideband_agc_release_ms`, `wideband_agc_max_gain_db`, `wideband_agc_min_gain_db`
- `orbass_enabled`, `orbass_amount`, `orbass_freq_hz`, `orbass_harmonics`, `orbass_drive`, `orbass_density`, `orbass_subharmonics_enabled`, `orbass_subharmonics_amount`
- `multiband_enabled`, `multiband_mode`, `multiband_low_hz`, `multiband_high_hz`, `multiband_x1_hz`, `multiband_x2_hz`, `multiband_x3_hz`, `multiband_x4_hz`, `multiband_low_threshold_db`, `multiband_mid_threshold_db`, `multiband_high_threshold_db`, `multiband_low_ratio`, `multiband_mid_ratio`, `multiband_high_ratio`, `multiband_low_attack_ms`, `multiband_mid_attack_ms`, `multiband_high_attack_ms`, `multiband_low_release_ms`, `multiband_mid_release_ms`, `multiband_high_release_ms`, `multiband_knee_db`, `multiband_link_strength`, `multiband_release_program_dependent`, `multiband_makeup_db`
- `stereo_widen_enabled`, `stereo_widen_width`, `stereo_widen_center`, `stereo_widen_mix`
- `limit_mpx`, `limit_lookahead_enabled`, `limit_lookahead_ms`, `limit_threshold`

Additional RDS keys in `RDS` (all optional):
- `en_rds`, `rds_level`, `pi`, `pty`, `tp`, `ta`, `ms`
- `ps_dynamic`, `rt_text`, `group_sequence`
- `en_rt_plus`, `rt_plus_format_a`, `rt_plus_format_b`
- `en_ptyn`, `ptyn`, `en_lps`, `ps_long_32`
- `rds_freq`, `rds_gaussian_enabled`, `rds_gaussian_bw_hz`

## Next steps

- replace input tap bridge with lower-level CoreAudio duplex callback for stricter realtime guarantees
- improve parity of multiband/orbass/widener behavior against Python implementation
- expand GUI controls toward Python parity
- add parity harness against Python test vectors

## Processing Bypass

The **Bypass** button does not provide a true audio bypass. Instead, it disables the creative processing blocks while keeping the essential FM encoding:

**Always active (not bypassed):**
- Input gain
- Low-pass filter (programLP)
- Pre-emphasis (50/75 µs)
- MPX encoding (pilot, stereo subcarrier, RDS)
- Deviation scaling and limiting
- Output gain

**Disabled when bypassed:**
- Wideband AGC
- HF trim
- Orbass bass enhancement
- Multiband compressor
- Stereo widener
- Stereo image protection

This allows quick A/B comparison between processed and unprocessed audio while maintaining FM broadcast compliance.

## Monitor Mode

When **Monitor Mode** is enabled, the output is the decoded audio after MPX encoding/decoding (pilot extraction + stereo demultiplexing). This is useful for hearing how the final FM signal will sound on a receiver.

Monitor always decodes through the MPX path regardless of bypass state. This means:
- Pre-emphasis is applied on encode, de-emphasis on decode
- Stereo is encoded as L-R subcarrier and decoded back
- Any MPX filtering or limiting affects the monitored output

Use Monitor Mode to verify your FM broadcast sounds correct before transmitting.

## Stereo Coder

The MPX stereo encoder generates FM composite signal at 192kHz sample rate:

| Component | Frequency | Status |
|-----------|-----------|--------|
| Pilot tone | 19 kHz | ✅ Phase-stable |
| Stereo subcarrier | 38 kHz | ✅ Phase-locked to pilot |
| RDS subcarrier | 57 kHz | ✅ Phase-locked to pilot (EN 50067) |

**Spectrum layout**: Pilot → Stereo (L-R up to 53kHz) → RDS (57kHz) → Headroom (59-96kHz)

The phase-locked carriers ensure no drift over long transmission periods.

## Input Level Guide

For FM broadcast, target these levels:

| Level Type | Recommended |
|------------|-------------|
| Peak | -18 to -6 dBFS |
| Average (RMS) | -24 to -20 dBFS |

Different broadcast standards:
- **US**: -20 dBFS nominal (maps from +4 dBu analog)
- **Europe (EBU R68)**: -18 dBFS nominal
- **Hot studios**: -6 dBFS peak ceiling

Tip: Watch the input meters while playing typical content. Keep average around -24 dB with peaks between -18 and -6 dBFS. If you're consistently hitting 0 dBFS (clipping), reduce input gain.
