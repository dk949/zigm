#!/bin/sh
#
# Shared test library, sourced by every tests/test_*.sh file.
#
# Sourcing this file:
#
#   * locates the zigm script and sources it with ZIGM_LIB=1, so its functions
#     are available and `main` does not run,
#   * defines the assertions below,
#   * creates a scratch directory in ZIGM_TMP.
#
# A test file ends with a call to `run_tests`, which runs every `test_*`
# function it defines, each in its own subshell, and prints a totals line the
# runner parses. An assertion that fails prints a message and exits the
# subshell, so the first failure ends that test but not the run.
#
# Portability: POSIX sh only, since the tests run under every shell zigm
# supports.

# Directory holding the tests, and the script under test.
ZIGM_TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ZIGM_BIN=${ZIGM_BIN:-$ZIGM_TEST_DIR/../zigm}

if [ ! -f "$ZIGM_BIN" ]; then
    printf 'tests: cannot find zigm at %s\n' "$ZIGM_BIN" >&2
    exit 1
fi

# How to invoke a shell for the end to end tests, set by the runner.
ZIGM_SHELL_CMD=${ZIGM_SHELL_CMD:-sh}

# Source zigm as a library. ZIGM_LIB is read by the script being sourced.
# shellcheck disable=SC2034
ZIGM_LIB=1
# shellcheck source=/dev/null
. "$ZIGM_BIN"

# zigm runs under `set -eu`. Keep -u, which catches unset variables in the code
# under test, but drop -e, since the assertions check statuses themselves.
set +e

# Scratch space, removed by run_tests.
ZIGM_TMP=$(mktemp -d 2>/dev/null) ||
    {
        printf 'tests: mktemp -d failed\n' >&2
        exit 1
    }

# Name of the running test, used in failure messages.
zigm_test_name='<none>'

# ---------------------------------------------------------------------------
# Assertions
#
# Each one ends the current test on failure.
# ---------------------------------------------------------------------------

# fail <message>
#
# Prints the reason and ends the test. The `not ok` line comes from run_tests,
# so a test that dies without an assertion is still reported.
fail() {
    printf '      %s\n' "$*"
    exit 1
}

# assert_eq <expected> <actual> [label]
assert_eq() {
    if [ "$1" != "$2" ]; then
        fail "${3:-values differ}: expected '$1', got '$2'"
    fi
}

# assert_ne <unexpected> <actual> [label]
assert_ne() {
    if [ "$1" = "$2" ]; then
        fail "${3:-values match}: did not expect '$2'"
    fi
}

# assert_contains <haystack> <needle> [label]
assert_contains() {
    case "$1" in
        *"$2"*) ;;
        *) fail "${3:-missing substring}: '$2' not found in '$1'" ;;
    esac
}

# assert_not_contains <haystack> <needle> [label]
assert_not_contains() {
    case "$1" in
        *"$2"*) fail "${3:-unexpected substring}: '$2' found in '$1'" ;;
    esac
}

# assert_status <expected status> <command> [arguments]
#
# The command runs in a subshell, so one that exits, as the require_* wrappers
# do on failure, ends there instead of ending the test. Output is discarded, so
# a command that reports on stderr stays quiet.
assert_status() {
    zigm_want=$1
    shift
    ("$@") >/dev/null 2>&1
    zigm_got=$?
    if [ "$zigm_got" -ne "$zigm_want" ]; then
        fail "'$*' exited $zigm_got, expected $zigm_want"
    fi
}

# assert_ok <command> [arguments]
assert_ok() {
    assert_status 0 "$@"
}

# assert_fails <command> [arguments]
assert_fails() {
    ("$@") >/dev/null 2>&1
    zigm_got=$?
    if [ "$zigm_got" -eq 0 ]; then
        fail "'$*' succeeded, expected failure"
    fi
}

# assert_out <expected stdout> <command> [arguments]
#
# Also requires the command to succeed.
assert_out() {
    zigm_want=$1
    shift
    zigm_got_out=$("$@" 2>/dev/null)
    zigm_got=$?
    if [ "$zigm_got" -ne 0 ]; then
        fail "'$*' exited $zigm_got, expected 0"
    fi
    if [ "$zigm_got_out" != "$zigm_want" ]; then
        fail "'$*' printed '$zigm_got_out', expected '$zigm_want'"
    fi
}

# assert_file <path> [label]
assert_file() {
    [ -f "$1" ] || fail "${2:-missing file}: $1"
}

# assert_dir <path> [label]
assert_dir() {
    [ -d "$1" ] || fail "${2:-missing directory}: $1"
}

# ---------------------------------------------------------------------------
# Running zigm as a program
# ---------------------------------------------------------------------------

# zigm_run <arguments>
#
# Runs the script end to end under the shell being tested, in a scratch HOME
# with the directory overrides pointed at scratch space, so a test never
# touches the real environment.
zigm_run() {
    # shellcheck disable=SC2086 # ZIGM_SHELL_CMD may carry options.
    env \
        HOME="$ZIGM_TMP/home" \
        ZIGM_DATA_DIR="$ZIGM_TMP/data" \
        ZIGM_CACHE_DIR="$ZIGM_TMP/cache" \
        ZIGM_CONFIG_DIR="$ZIGM_TMP/config" \
        ZIGM_LIB=0 \
        $ZIGM_SHELL_CMD "$ZIGM_BIN" "$@"
}

# zigm_run_out <arguments>
#
# Same, with stderr folded into stdout so a test can inspect both.
zigm_run_out() {
    zigm_run "$@" 2>&1
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

# Prints the names of the `test_*` functions the calling file defines, in file
# order. Reading the file is the portable way to do this, since listing defined
# functions differs between shells.
zigm_list_tests() {
    sed -n 's/^\(test_[A-Za-z0-9_]*\)[[:space:]]*().*/\1/p' "$0"
}

# Runs every test in the calling file and prints a totals line.
run_tests() {
    zigm_pass=0
    zigm_fail=0

    for zigm_test_name in $(zigm_list_tests); do
        zigm_report=$("$zigm_test_name")
        zigm_status=$?

        if [ "$zigm_status" -eq 0 ]; then
            printf 'ok - %s\n' "$zigm_test_name"
            zigm_pass=$((zigm_pass + 1))
        else
            printf 'not ok - %s\n' "$zigm_test_name"
            zigm_fail=$((zigm_fail + 1))
        fi

        if [ -n "$zigm_report" ]; then
            printf '%s\n' "$zigm_report"
        fi
    done

    rm -rf "$ZIGM_TMP"

    printf '# totals %d %d\n' "$zigm_pass" "$zigm_fail"
    [ "$zigm_fail" -eq 0 ]
}
