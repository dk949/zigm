#!/bin/sh
#
# Test runner.
#
# Usage:
#
#   tests/run.sh [test file ...]
#
# With no arguments it runs every tests/test_*.sh file. The SHELLS environment
# variable selects the shells to run under, defaulting to `sh`:
#
#   SHELLS='dash bash mksh' tests/run.sh
#
# Each shell first gets a syntax check of zigm, then runs every test file. A
# missing shell is an error, not a skip, so a shell silently dropping out of CI
# cannot go unnoticed.

set -u

ZIGM_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ZIGM_BIN=$ZIGM_ROOT/zigm
export ZIGM_BIN

SHELLS=${SHELLS:-sh}

# shell_command <name>
#
# Prints how to invoke that shell in POSIX mode. zsh follows sh rules only when
# told to, and busybox keeps its shell behind a subcommand.
shell_command() {
    case "$1" in
        zsh) printf 'zsh --emulate sh' ;;
        busybox) printf 'busybox sh' ;;
        *) printf '%s' "$1" ;;
    esac
}

if [ "$#" -gt 0 ]; then
    files=$*
else
    files=$(ls "$ZIGM_ROOT"/tests/test_*.sh)
fi

if [ -z "$files" ]; then
    printf 'tests: no test files found\n' >&2
    exit 1
fi

total_pass=0
total_fail=0
failed_shells=''

for shell_name in $SHELLS; do
    shell_cmd=$(shell_command "$shell_name")

    if ! command -v "${shell_cmd%% *}" >/dev/null 2>&1; then
        printf 'tests: shell not found: %s\n' "$shell_name" >&2
        failed_shells="$failed_shells $shell_name"
        continue
    fi

    printf '\n=== %s ===\n' "$shell_cmd"

    # Syntax check before running anything, so a parse error under one shell
    # reads as a parse error rather than as every test failing.
    syntax_ok=1
    for file in "$ZIGM_BIN" "$ZIGM_ROOT/tests/lib.sh"; do
        # shellcheck disable=SC2086 # shell_cmd may carry options.
        $shell_cmd -n "$file" || syntax_ok=0
    done

    if [ "$syntax_ok" -eq 0 ]; then
        printf 'not ok - %s -n\n' "$shell_cmd"
        failed_shells="$failed_shells $shell_name"
        continue
    fi
    printf 'ok - %s -n\n' "$shell_cmd"

    shell_failed=0

    for file in $files; do
        # shellcheck disable=SC2086 # shell_cmd may carry options.
        output=$(ZIGM_SHELL_CMD="$shell_cmd" $shell_cmd "$file" 2>&1)
        status=$?

        printf '%s\n' "$output" | grep -v '^# totals '

        totals=$(printf '%s\n' "$output" | sed -n 's/^# totals //p')
        if [ -n "$totals" ]; then
            pass=${totals%% *}
            fail=${totals##* }
            total_pass=$((total_pass + pass))
            total_fail=$((total_fail + fail))
        fi

        if [ "$status" -ne 0 ]; then
            shell_failed=1
            if [ -z "$totals" ]; then
                printf 'not ok - %s died with status %d\n' "$file" "$status"
                total_fail=$((total_fail + 1))
            fi
        fi
    done

    if [ "$shell_failed" -ne 0 ]; then
        failed_shells="$failed_shells $shell_name"
    fi
done

printf '\n%d passed, %d failed\n' "$total_pass" "$total_fail"

if [ -n "$failed_shells" ]; then
    printf 'failing shells:%s\n' "$failed_shells" >&2
    exit 1
fi

exit 0
