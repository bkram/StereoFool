#!/bin/bash
# Run MPX Prime with an optimized release build for normal use.

set -e

cd "$(dirname "$0")"

echo "Running MPX Prime (release, arm64)..."
swift run --package-path macOS -c release --arch arm64 MPXPrime "$@"
