#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
LOG_FILE="$BUILD_DIR/flash_history.log"
LAST_EPOCH_FILE="$BUILD_DIR/last_flash_epoch.txt"
LAST_UTC_FILE="$BUILD_DIR/last_flash_utc.txt"
LAST_LOCAL_FILE="$BUILD_DIR/last_flash_local.txt"

mkdir -p "$BUILD_DIR"

start_epoch="$(date +%s)"
start_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
start_local="$(date +"%Y-%m-%d %H:%M:%S %Z")"

echo "[$start_utc] flash_start epoch=$start_epoch local=\"$start_local\"" | tee -a "$LOG_FILE"

"$ROOT_DIR/scripts/flash_jlink.sh"

end_epoch="$(date +%s)"
end_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
end_local="$(date +"%Y-%m-%d %H:%M:%S %Z")"
flash_secs="$((end_epoch - start_epoch))"

printf '%s\n' "$start_epoch" > "$LAST_EPOCH_FILE"
printf '%s\n' "$start_utc" > "$LAST_UTC_FILE"
printf '%s\n' "$start_local" > "$LAST_LOCAL_FILE"

echo "[$end_utc] flash_done duration_sec=$flash_secs local=\"$end_local\"" | tee -a "$LOG_FILE"
echo "recorded_start_utc=$start_utc"
echo "recorded_start_local=$start_local"
