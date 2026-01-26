#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS only." >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"<output device name>\"" >&2
  echo "Example: $0 \"USB Audio DAC\"" >&2
  exit 2
fi

DEVICE_NAME="$1"

if command -v AudioDevice >/dev/null 2>&1; then
  # Set sample rate and bit depth if the CLI is available.
  AudioDevice set --device "$DEVICE_NAME" --rate 192000 --bit-depth 24
else
  echo "AudioDevice not found; cannot set 192kHz/24-bit via CLI." >&2
  echo "Install with: brew install audiodevice (or your preferred package source)" >&2
fi

# Maximize output volume and ensure it is not muted.
osascript -e 'set volume output volume 100' -e 'set volume output muted false'

echo "Audio setup complete for: $DEVICE_NAME"
