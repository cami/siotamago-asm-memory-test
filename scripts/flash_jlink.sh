#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HEX="$ROOT_DIR/build/main.hex"
CMD_FILE="$ROOT_DIR/build/jlink_cmds.txt"
PIO_JLINK="${HOME}/.platformio/packages/tool-jlink/JLinkExe"

if [[ ! -f "$HEX" ]]; then
    echo "error: $HEX not found. Run ./scripts/build.sh first." >&2
    exit 1
fi

if [[ -x "$PIO_JLINK" ]]; then
    JLINK_EXE="$PIO_JLINK"
elif command -v JLinkExe >/dev/null 2>&1; then
    JLINK_EXE="$(command -v JLinkExe)"
else
    echo "error: JLinkExe not found." >&2
    echo "run: pio pkg install --global --tool tool-jlink" >&2
    exit 1
fi

mkdir -p "$ROOT_DIR/build"

cat > "$CMD_FILE" <<'EOF'
r
h
loadfile build/main.hex
r
g
q
EOF

"$JLINK_EXE" \
    -device nRF52840_xxAA \
    -if SWD \
    -speed 4000 \
    -autoconnect 1 \
    -CommanderScript "$CMD_FILE"
