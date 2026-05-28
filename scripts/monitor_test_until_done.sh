#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_SCRIPT="$ROOT_DIR/scripts/check_test_elapsed.sh"
INTERVAL_SEC=5
MAX_SEC=1800

usage() {
    cat <<'EOF'
Usage:
  ./scripts/monitor_test_until_done.sh [--interval N] [--max-seconds N] [--once]

Options:
  --interval N      Poll interval seconds (default: 5)
  --max-seconds N   Max monitoring duration seconds (default: 1800)
  --once            Run one check and exit
  -h, --help        Show this help

Exit codes:
  0: pass_loop reached
  2: fail_loop reached
  3: timeout reached
  4: unknown state while monitoring
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --interval)
            INTERVAL_SEC="$2"
            shift 2
            ;;
        --max-seconds)
            MAX_SEC="$2"
            shift 2
            ;;
        --once)
            INTERVAL_SEC=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ ! -x "$CHECK_SCRIPT" ]]; then
    echo "error: $CHECK_SCRIPT not executable." >&2
    exit 1
fi

if ! [[ "$INTERVAL_SEC" =~ ^[0-9]+$ ]]; then
    echo "error: --interval must be non-negative integer." >&2
    exit 1
fi

if ! [[ "$MAX_SEC" =~ ^[0-9]+$ ]]; then
    echo "error: --max-seconds must be non-negative integer." >&2
    exit 1
fi

started_epoch="$(date +%s)"

while true; do
    now_local="$(date +"%Y-%m-%d %H:%M:%S %Z")"
    echo "[$now_local]"

    output="$($CHECK_SCRIPT)"
    echo "$output"

    state="$(printf '%s\n' "$output" | sed -n 's/^state=//p' | head -n1)"

    if [[ "$state" == "pass_loop" ]]; then
        echo "result=PASS"
        exit 0
    fi

    if [[ "$state" == "fail_loop" ]]; then
        echo "result=FAIL"
        exit 2
    fi

    if [[ "$state" != "test_running" && "$state" != "boot_or_reset_phase" ]]; then
        echo "result=UNKNOWN state=$state"
        exit 4
    fi

    now_epoch="$(date +%s)"
    run_sec="$((now_epoch - started_epoch))"
    if [[ "$run_sec" -ge "$MAX_SEC" ]]; then
        echo "result=TIMEOUT monitored_sec=$run_sec"
        exit 3
    fi

    if [[ "$INTERVAL_SEC" -eq 0 ]]; then
        exit 0
    fi

    sleep "$INTERVAL_SEC"
done
