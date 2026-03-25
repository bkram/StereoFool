#!/bin/bash
# Run StereoFool with an optimized release build for normal use.

set -e

cd "$(dirname "$0")"

echo "Running StereoFool (release, arm64)..."
swift run --package-path macOS -c release --arch arm64 StereoFool "$@"
