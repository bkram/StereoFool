#!/bin/bash
# Run MPX Prime with a debug build for development work.

set -e

cd "$(dirname "$0")"

echo "Running MPX Prime (debug, arm64)..."
swift run --package-path macOS -c debug --arch arm64 MPXPrime "$@"
