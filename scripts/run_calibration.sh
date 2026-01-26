#!/usr/bin/env bash
set -euo pipefail

CONFIG="stereofool.ini"
WAV="output.wav"
LENGTH="10"
ITERATIONS="5"
ENABLE_RDS="false"
TARGET_PILOT="8"
TARGET_RDS_KHZ="2.0"

usage() {
  cat <<'EOF'
Usage: scripts/run_calibration.sh [options]

Options:
  -c, --config PATH        Config file (default: stereofool.ini)
  -w, --wav PATH           WAV output path (default: output.wav)
  -l, --length SECONDS     Capture length per iteration (default: 10)
  -i, --iterations N       Iterations (default: 5)
  --enable-rds             Include RDS in calibration
  --pilot PCT              Pilot target percent (default: 8)
  --rds-khz KHZ            RDS target deviation (default: 2.0)
  -h, --help               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      CONFIG="$2"
      shift 2
      ;;
    -w|--wav)
      WAV="$2"
      shift 2
      ;;
    -l|--length)
      LENGTH="$2"
      shift 2
      ;;
    -i|--iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    --enable-rds)
      ENABLE_RDS="true"
      shift
      ;;
    --pilot)
      TARGET_PILOT="$2"
      shift 2
      ;;
    --rds-khz)
      TARGET_RDS_KHZ="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

ARGS=(
  "--config" "$CONFIG"
  "--wav" "$WAV"
  "--length" "$LENGTH"
  "--iterations" "$ITERATIONS"
  "--target-pilot-pct" "$TARGET_PILOT"
  "--target-rds-khz" "$TARGET_RDS_KHZ"
)

if [[ "$ENABLE_RDS" == "true" ]]; then
  ARGS+=("--enable-rds")
fi

python tools/calibrate_mpx.py "${ARGS[@]}"
