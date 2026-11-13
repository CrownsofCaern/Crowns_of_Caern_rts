#!/usr/bin/env bash
# Headless tests for the Warbound spinoff. Fails on test failures and on script errors.
#
#   ./run_tests.sh [--slow] [filter]
#
# The tests run in TEST_JOBS Godot processes (default: one per CPU core) that
# share the test files through a queue directory. --slow adds the long tests
# that test files list in their SLOW constant (long simulations, AI matches).
set -uo pipefail
GODOT="${GODOT:-godot}"
SLOW=()
FILTER=""
for arg in "$@"; do
  if [[ "$arg" == "--slow" ]]; then SLOW=(--slow); else FILTER="$arg"; fi
done
cd "$(dirname "$0")"
JOBS="${TEST_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
start=$(date +%s)
# A cold import on a fresh checkout can crash Godot part-way (seen on macOS);
# repeat it, or every test that loads a texture fails.
for attempt in 1 2 3; do
  if "$GODOT" --headless --path . --import >/dev/null 2>&1; then break; fi
  if [[ $attempt -eq 3 ]]; then echo "Godot --import failed three times." >&2; exit 1; fi
  echo "Godot --import crashed (attempt $attempt); retrying." >&2
done

# Each Godot process gets its own empty home, so parallel runners never share
# user:// (saves, settings), and tests never touch your own saves.
isolated() {
  local home="$tmp/home_$1"
  mkdir -p "$home"
  HOME="$home" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" "${@:2}"
}
mkdir -p "$tmp/queue"
for ((i = 0; i < JOBS; i++)); do
  (isolated "$i" "$GODOT" --headless --path . --script res://tests/run_tests.gd -- "$FILTER" ${SLOW[@]+"${SLOW[@]}"} --queue "$tmp/queue" \
    >"$tmp/unit_$i.log" 2>&1; echo $? >"$tmp/unit_$i.code") &
done
wait

code=0
total=0
failed=0
skipped=0
for ((i = 0; i < JOBS; i++)); do
  out=$(cat "$tmp/unit_$i.log")
  echo "$out" | grep -E "^(PASS|FAIL) |^  - "
  if [[ "$(cat "$tmp/unit_$i.code")" != 0 ]]; then code=1; fi
  if echo "$out" | grep -qE "SCRIPT ERROR|Parse Error|Failed to load script"; then
    echo "$out" | grep -E -A3 "SCRIPT ERROR|Parse Error|Failed to load script"
    echo "Detected script errors in test run." >&2
    code=1
  fi
  summary=$(echo "$out" | grep -E "^[0-9]+ tests, [0-9]+ failed" | tail -1)
  if [[ -z "$summary" ]]; then
    echo "Test runner $i ended without a summary:" >&2
    echo "$out" | tail -20 >&2
    code=1
  else
    total=$((total + $(echo "$summary" | cut -d' ' -f1)))
    failed=$((failed + $(echo "$summary" | cut -d' ' -f3)))
    skipped=$((skipped + $(echo "$summary" | sed -E 's/.*\(([0-9]+) slow tests skipped.*/\1/')))
  fi
done
if [[ $total -eq 0 ]]; then code=1; fi
echo ""
echo "$total tests, $failed failed ($JOBS runners; $skipped slow tests skipped, run with --slow)"
echo "Finished in $(($(date +%s) - start))s."
exit $code
