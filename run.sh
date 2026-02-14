#!/bin/bash
# Run StereoFool in release mode optimized for Apple Silicon

set -e

cd "$(dirname "$0")"

echo "Running StereoFool (arm64 optimized)..."
swift run --package-path macOS -c debug --arch arm64 StereoFool "$@"
