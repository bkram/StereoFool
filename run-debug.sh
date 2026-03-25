#!/bin/bash
# Run StereoFool with a debug build for development work.

set -e

cd "$(dirname "$0")"

echo "Running StereoFool (debug, arm64)..."
swift run --package-path macOS -c debug --arch arm64 StereoFool "$@"
