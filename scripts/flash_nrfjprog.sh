#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HEX="$ROOT_DIR/build/main.hex"

if [[ ! -f "$HEX" ]]; then
    echo "error: $HEX not found. Run ./scripts/build.sh first." >&2
    exit 1
fi

if ! command -v nrfjprog >/dev/null 2>&1; then
    echo "error: nrfjprog not found." >&2
    exit 1
fi

nrfjprog -f nrf52 --eraseall
nrfjprog -f nrf52 --program "$HEX"
nrfjprog -f nrf52 --reset

echo "flashed: $HEX"
