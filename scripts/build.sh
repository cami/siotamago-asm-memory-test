#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
SRC="$ROOT_DIR/src/main.S"
OBJ="$BUILD_DIR/main.o"
ELF="$BUILD_DIR/main.elf"
HEX="$BUILD_DIR/main.hex"
LD_SCRIPT="$ROOT_DIR/linker.ld"

if command -v pio >/dev/null 2>&1; then
    PIO_BIN="$(command -v pio)"
elif [[ -x "${HOME}/.platformio/penv/bin/pio" ]]; then
    PIO_BIN="${HOME}/.platformio/penv/bin/pio"
else
    echo "error: pio command not found. Install PlatformIO Core first." >&2
    exit 1
fi

TOOLCHAIN_DIR="${HOME}/.platformio/packages/toolchain-gccarmnoneeabi/bin"
AS="$TOOLCHAIN_DIR/arm-none-eabi-as"
LD_BIN="$TOOLCHAIN_DIR/arm-none-eabi-ld"
OBJCOPY="$TOOLCHAIN_DIR/arm-none-eabi-objcopy"

if [[ ! -x "$AS" || ! -x "$LD_BIN" || ! -x "$OBJCOPY" ]]; then
    echo "error: toolchain not found in $TOOLCHAIN_DIR" >&2
    echo "run: pio pkg install --global --tool toolchain-gccarmnoneeabi" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"

"$AS" -g -mcpu=cortex-m4 -mthumb "$SRC" -o "$OBJ"
"$LD_BIN" -T "$LD_SCRIPT" "$OBJ" -o "$ELF"
"$OBJCOPY" -O ihex "$ELF" "$HEX"

echo "built: $HEX"
