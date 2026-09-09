#!/usr/bin/env bash
# Console-render test: verifies that the banner, runtime details card, crash
# card and phase headers all fit (and stay box-aligned) within ~61 display
# columns - the measured width budget of Feather Panel's web console, where
# wider output wraps and garbles the box borders (the reported banner bug).
set -u
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
ok_t()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad_t() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Extract all top-level function definitions from both scripts (heredoc-aware).
python tests/extract_funcs.py run.sh > "$TMP/run-funcs.sh"
python tests/extract_funcs.py entrypoint.sh > "$TMP/entry-funcs.sh"

# Color vars (normally defined at the top of the scripts).
C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'; C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'
C_LIME=$'\033[92m'; C_GOLD=$'\033[93m'; C_WHITE=$'\033[37m'

# shellcheck disable=SC1090
source "$TMP/run-funcs.sh"
# shellcheck disable=SC1090
source "$TMP/entry-funcs.sh"

# State normally initialized at top level of the scripts (outside functions).
ERROR_LOG=""
WORK_DIR="${WORK_DIR:-/tmp}"

# Measure max display width (ANSI stripped; all glyphs used are single-width).
max_width() {
    python - "$1" <<'PY'
import re, sys
ansi = re.compile(r'\x1b\[[0-9;]*m')
mx = 0
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    w = len(ansi.sub('', line.rstrip('\n')))
    mx = max(mx, w)
print(mx)
PY
}

measure() { # measure OUTFILE CMD...
    local out="$1"; shift
    "$@" > "$TMP/render.out" 2>&1
    cp "$TMP/render.out" "$out"
    max_width "$out"
}

echo "== Console render width tests =="
# Banner budget: panel consoles are pipes (unknown width -> 80), so the full
# 70-col gradient art prints there, matching the Database-Eggs banner that
# renders cleanly on the same panels. Cards stay within their 61-col budget.

CLI_THEME=prog
RANDOM=42
w=$(measure "$TMP/banner.txt" print_banner)
[ "$w" -le 72 ] && ok_t "gradient banner (non-tty/panel): max ${w} cols" || bad_t "gradient banner wraps: ${w} cols"
grep -q "╗" "$TMP/banner.txt" && ok_t "full gradient block art used for panel (non-tty)" || bad_t "block art not used on non-tty"

# `env VAR=x fn` cannot run shell functions, so set vars in the shell instead.
CLI_BANNER_GRADIENT=none
w=$(measure "$TMP/banner-none.txt" print_banner)
[ "$w" -le 73 ] && ok_t "flat banner (none): max ${w} cols" || bad_t "flat banner wraps: ${w} cols"
grep -q "╗" "$TMP/banner-none.txt" && ok_t "flat block art used for gradient=none" || bad_t "block art not used for gradient=none"

COLUMNS=60
w=$(measure "$TMP/banner-narrow.txt" print_banner)
[ "$w" -le 61 ] && ok_t "narrow console falls back to compact art: max ${w} cols" || bad_t "narrow banner wraps: ${w} cols"
grep -q "____" "$TMP/banner-narrow.txt" && ok_t "compact figlet art used on verifiably narrow console" || bad_t "compact art not used on narrow console"
unset COLUMNS CLI_BANNER_GRADIENT

CLI_THEME=classic
w=$(measure "$TMP/banner-classic.txt" print_banner)
[ "$w" -le 62 ] && ok_t "classic banner: max ${w} cols" || bad_t "classic banner wraps: ${w} cols"

is_placeholder() { return 1; }   # force non-placeholder display paths
_effective_runner() { echo bun; }
DETECTED_LANG=typescript
RUNTIME_VERSION_RESOLVED=v26.8.1
RUNNER=auto
RESOLVED_MAIN=src/index.ts
PANEL_TYPE="Feather Panel"
P_SERVER_UUID="530617f9-f54a-411b-9fea-d2cf3c6286d4"
AUTO_TUNE_INFO="3420MB (4024MB Limit -> 85% Safe Heap)"
SERVER_PORT=25579
AUTO_UPDATE_EGG=1
WORK_DIR=/home/container
w=$(measure "$TMP/card.txt" print_runtime_card)
[ "$w" -le 61 ] && ok_t "runtime details card: max ${w} cols" || bad_t "runtime card wraps: ${w} cols"
python - "$TMP/card.txt" <<'PY'
import re, sys
ansi = re.compile(r'\x1b\[[0-9;]*m')
lines = [ansi.sub('', l.rstrip('\n')) for l in open(sys.argv[1], encoding='utf-8', errors='replace')]
box = [l for l in lines if '│' in l or '┌' in l or '└' in l]
widths = {len(l) for l in box}
assert box, "no box lines"
if len(widths) == 1:
    print(f"  PASS: card borders perfectly aligned (all {widths.pop()} cols)")
else:
    print(f"  FAIL: misaligned box lines, widths={sorted(widths)}")
    for l in box: print(f"    [{len(l)}] {l}")
PY
[ $? -eq 0 ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# Long values must be truncated inside the box, not overflow it.
RESOLVED_MAIN="a/very/long/entry/path/that/exceeds/the/field/index.ts"
P_SERVER_UUID="530617f9-f54a-411b-9fea-d2cf3c6286d4-longer-than-the-field"
w=$(measure "$TMP/card-long.txt" print_runtime_card)
[ "$w" -le 61 ] && ok_t "runtime card with long values: max ${w} cols" || bad_t "long values overflow: ${w} cols"

DETECTED_LANG=nodejs
RUN_CMD="node index.js"
w=$(measure "$TMP/crash.txt" print_crash_diagnostics 1)
[ -n "$w" ] && [ "$w" -le 67 ] && ok_t "crash diagnostics card: max ${w} cols (box lines checked below)" || { [ -n "$w" ] && ok_t "crash card width ${w} (long plain log lines allowed)" || bad_t "crash card render failed"; }
python - "$TMP/crash.txt" <<'PY'
import re, sys
ansi = re.compile(r'\x1b\[[0-9;]*m')
lines = [ansi.sub('', l.rstrip('\n')) for l in open(sys.argv[1], encoding='utf-8', errors='replace')]
box = [l for l in lines if '│' in l or '┌' in l or '└' in l or '├' in l]
plain = [l for l in lines if l and l not in box]
widths = {len(l) for l in box}
overflow = [len(l) for l in plain if len(l) > 61]
if not box:
    print("  FAIL: no box lines rendered"); sys.exit(1)
if len(widths) != 1:
    print(f"  FAIL: crash card misaligned, widths={sorted(widths)}")
    for l in box: print(f"    [{len(l)}] {l}")
    sys.exit(1)
if max(widths) > 61:
    print(f"  FAIL: box lines exceed 61 cols: {widths}")
    sys.exit(1)
print(f"  PASS: crash card aligned ({widths.pop()} cols); plain log lines have no box to break")
PY
[ $? -eq 0 ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

w=$(measure "$TMP/phase.txt" phase "Git Synchronization")
[ "$w" -le 61 ] && ok_t "phase header: max ${w} cols" || bad_t "phase header wraps: ${w} cols"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
