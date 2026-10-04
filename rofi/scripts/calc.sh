#!/usr/bin/env bash
# calc.sh - "Calc" tab of the rofi launcher: qalc-backed script mode.
# Wired as  calc:<path>  in the launcher's -modes string.
#
# rofi calls this script with no arguments at startup (ROFI_RETV=0), then
# again with the selected or typed text as $1. Empty stdout makes rofi quit,
# so the startup call must always print an entry.

set -u

HINT='Type an expression, e.g. 2+2*10'

if [ "${ROFI_RETV:-0}" -eq 0 ] || [ $# -eq 0 ]; then
    printf '%s\n' "$HINT"
    exit 0
fi

# Selecting the hint row itself must not feed that sentence to qalc.
if [ "$1" = "$HINT" ]; then
    printf '%s\n' "$HINT"
    exit 0
fi

command -v qalc >/dev/null 2>&1 || { printf '%s\n' "$HINT"; exit 0; }

result=$(qalc -t -- "$1" 2>/dev/null | tail -n 1)
[ -n "$result" ] || result=$HINT

printf '%s\n' "$result"
