#!/bin/bash
# Build StereoFool in release mode optimized for Apple Silicon

set -e

cd "$(dirname "$0")"

echo "Building StereoFool (arm64 release)..."
swift build --package-path macOS -c release --arch arm64

echo "Build complete!"
