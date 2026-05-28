#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
LAST_EPOCH_FILE="$BUILD_DIR/last_flash_epoch.txt"
ELF="$BUILD_DIR/main.elf"
TOOLCHAIN_DIR="${HOME}/.platformio/packages/toolchain-gccarmnoneeabi/bin"
NM_BIN="$TOOLCHAIN_DIR/arm-none-eabi-nm"
PIO_JLINK="${HOME}/.platformio/packages/tool-jlink/JLinkExe"

FLASH_START=0x00000000
FLASH_END=0x00100000
FLASH_CURSOR_RAM=0x2003B200
TEST_STATE_RAM=0x2003B204

if [[ ! -f "$LAST_EPOCH_FILE" ]]; then
    echo "error: $LAST_EPOCH_FILE not found. Run ./scripts/flash_and_record.sh first." >&2
    exit 1
fi

if [[ -x "$PIO_JLINK" ]]; then
    JLINK_EXE="$PIO_JLINK"
elif command -v JLinkExe >/dev/null 2>&1; then
    JLINK_EXE="$(command -v JLinkExe)"
else
    echo "error: JLinkExe not found." >&2
    exit 1
fi

if [[ ! -x "$NM_BIN" ]]; then
    echo "error: $NM_BIN not found." >&2
    exit 1
fi

if [[ ! -f "$ELF" ]]; then
    echo "error: $ELF not found. Build first." >&2
    exit 1
fi

last_epoch="$(cat "$LAST_EPOCH_FILE")"
now_epoch="$(date +%s)"
elapsed_sec="$((now_epoch - last_epoch))"

jlink_cmd="$(mktemp)"
trap 'rm -f "$jlink_cmd"' EXIT
cat > "$jlink_cmd" <<'EOF'
h
regs
mem32 0xE000ED04 1
mem32 0xE000ED28 1
mem32 0x2003B200 1
mem32 0x2003B204 1
q
EOF

jlink_out="$("$JLINK_EXE" -NoGui 1 -Device NRF52840_XXAA -If SWD -Speed 4000 -AutoConnect 1 -CommandFile "$jlink_cmd")"
pc_hex="$(printf '%s\n' "$jlink_out" | sed -n 's/^PC = \([0-9A-Fa-f]*\),.*/\1/p' | head -n1 | tr 'a-f' 'A-F')"
ipsr_dec="$(printf '%s\n' "$jlink_out" | sed -n 's/.*IPSR = \([0-9][0-9]*\).*/\1/p' | head -n1)"
cfsr_hex="$(printf '%s\n' "$jlink_out" | sed -n 's/^E000ED28 = \([0-9A-Fa-f]*\).*/\1/p' | head -n1 | tr 'a-f' 'A-F')"
cursor_hex="$(printf '%s\n' "$jlink_out" | sed -n 's/^2003B200 = \([0-9A-Fa-f]*\).*/\1/p' | head -n1 | tr 'a-f' 'A-F')"
state_flag_hex="$(printf '%s\n' "$jlink_out" | sed -n 's/^2003B204 = \([0-9A-Fa-f]*\).*/\1/p' | head -n1 | tr 'a-f' 'A-F')"

if [[ -z "$pc_hex" ]]; then
    echo "error: could not read PC from J-Link output." >&2
    exit 1
fi

pc_dec="$((16#$pc_hex))"
flash_start_dec="$((FLASH_START))"
flash_end_dec="$((FLASH_END))"
flash_total_bytes="$((flash_end_dec - flash_start_dec))"

sym_to_dec() {
    local sym="$1"
    local hex
    hex="$("$NM_BIN" -n "$ELF" | awk -v s="$sym" '$3==s {print $1; exit}')"
    if [[ -z "$hex" ]]; then
        echo ""
    else
        echo "$((16#$hex))"
    fi
}

stage_pass="$(sym_to_dec stage_pass)"
stage_fail="$(sym_to_dec stage_fail)"
flash_test_range="$(sym_to_dec flash_test_range)"
pass_loop="$(sym_to_dec stage_pass_loop)"
fail_loop="$(sym_to_dec stage_fail_loop)"
stage_start="$(sym_to_dec flash_stage_start)"
stage_end="$(sym_to_dec flash_stage_end)"

# flash stage is copied to RAM at 0x2003E000 before execution.
stage_base=0x2003E000
pc_stage_dec="$pc_dec"
if [[ "$pc_dec" -ge "$stage_base" ]]; then
    pc_stage_dec="$((pc_dec - stage_base))"
fi

state="unknown"
if [[ -n "$state_flag_hex" && "$state_flag_hex" == "00000001" ]]; then
    state="pass_loop"
elif [[ -n "$state_flag_hex" && "$state_flag_hex" == "00000002" ]]; then
    state="fail_loop"
elif [[ -n "$stage_pass" && -n "$stage_fail" && "$pc_stage_dec" -ge "$stage_pass" && "$pc_stage_dec" -lt "$stage_fail" ]]; then
    state="pass_loop"
elif [[ -n "$stage_fail" && -n "$flash_test_range" && "$pc_stage_dec" -ge "$stage_fail" && "$pc_stage_dec" -lt "$flash_test_range" ]]; then
    state="fail_loop"
elif [[ -n "$pass_loop" && "$pc_stage_dec" -eq "$pass_loop" ]]; then
    state="pass_loop"
elif [[ -n "$fail_loop" && "$pc_stage_dec" -eq "$fail_loop" ]]; then
    state="fail_loop"
elif [[ -n "$stage_start" && -n "$stage_end" && "$pc_stage_dec" -ge "$stage_start" && "$pc_stage_dec" -lt "$stage_end" ]]; then
    state="test_running"
elif [[ "$pc_dec" -lt 0x1000 ]]; then
    state="boot_or_reset_phase"
fi

elapsed_min="$((elapsed_sec / 60))"
elapsed_rem="$((elapsed_sec % 60))"

printf 'elapsed=%dm%02ds\n' "$elapsed_min" "$elapsed_rem"
printf 'pc=0x%s ipsr=%s cfsr=0x%s\n' "$pc_hex" "${ipsr_dec:-?}" "${cfsr_hex:-?}"
printf 'state=%s\n' "$state"

if [[ "$state" == "test_running" && -n "$cursor_hex" ]]; then
    cursor_dec="$((16#$cursor_hex))"
    if [[ "$cursor_dec" -ge "$flash_start_dec" && "$cursor_dec" -le "$flash_end_dec" ]]; then
        done_bytes="$((cursor_dec - flash_start_dec))"
        if [[ "$done_bytes" -gt "$flash_total_bytes" ]]; then
            done_bytes="$flash_total_bytes"
        fi
        progress_x10000=0
        if [[ "$flash_total_bytes" -gt 0 ]]; then
            progress_x10000="$((done_bytes * 10000 / flash_total_bytes))"
        fi
        progress_int="$((progress_x10000 / 100))"
        progress_frac="$((progress_x10000 % 100))"

        printf 'progress=%d.%02d%% page_addr=0x%s\n' "$progress_int" "$progress_frac" "$cursor_hex"

        if [[ "$done_bytes" -gt 0 ]]; then
            remain_bytes="$((flash_total_bytes - done_bytes))"
            remain_sec="$((elapsed_sec * remain_bytes / done_bytes))"
            remain_min="$((remain_sec / 60))"
            remain_rem="$((remain_sec % 60))"
            eta_epoch="$((now_epoch + remain_sec))"
            eta_local="$(date -d "@$eta_epoch" +"%Y-%m-%d %H:%M:%S %Z")"
            printf 'remaining~=%dm%02ds eta_local="%s"\n' "$remain_min" "$remain_rem" "$eta_local"
        fi
    fi
fi

if [[ "$state" == "test_running" && "$elapsed_sec" -gt 900 ]]; then
    echo "note: elapsed is over 15 minutes while still running (longer than typical)."
fi
