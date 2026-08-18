#!/bin/sh
#
# Tests for the download layer: the command line each downloader is given, the
# retry loop around it, and the reason a failed download reports.
#
# Nothing here touches the network. `curl` and `wget` are replaced with shell
# functions that record the arguments they were called with and answer however
# the test wants them to. A stub runs inside a command substitution, so it
# counts its own calls in a file rather than in a variable, which would not
# survive the subshell.

# The stub functions below are called by the code under test, never directly,
# and the globals set below are read by the sourced zigm, not by this file.
# shellcheck disable=SC2329,SC2034

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# zigm_record <file> <arguments>
#
# Appends the arguments a stub was called with, one call to a line.
zigm_record() {
    zigm_record_file=$1
    shift
    printf '%s\n' "$*" >>"$zigm_record_file"
}

# zigm_calls <file>
#
# Prints how many calls the file records. `wc -l` pads its count on some
# systems, and awk does not.
zigm_calls() {
    awk 'END { print NR }' "$1"
}

# ---------------------------------------------------------------------------
# Command lines
# ---------------------------------------------------------------------------

test_curl_takes_a_timeout_for_a_body() {
    zigm_log="$ZIGM_TMP/curl-body"
    : >"$zigm_log"
    curl() {
        zigm_record "$zigm_log" "$@"
        printf 'body\n'
    }

    ZIGM_DOWNLOADER=curl
    ZIGM_CONNECT_TIMEOUT=7

    assert_out body fetch_stdout https://example.invalid/a
    assert_eq '--connect-timeout 7 -fsSL -- https://example.invalid/a' \
        "$(cat "$zigm_log")" 'command line'
}

test_curl_takes_a_timeout_for_a_file() {
    zigm_log="$ZIGM_TMP/curl-file"
    zigm_dest="$ZIGM_TMP/curl-dest"
    : >"$zigm_log"
    curl() {
        zigm_record "$zigm_log" "$@"
        printf 'body\n' >"$zigm_dest"
    }

    ZIGM_DOWNLOADER=curl
    ZIGM_CONNECT_TIMEOUT=7

    assert_ok fetch_file https://example.invalid/b "$zigm_dest"
    assert_eq "--connect-timeout 7 -fsSL -o $zigm_dest -- https://example.invalid/b" \
        "$(cat "$zigm_log")" 'command line'
    assert_eq body "$(cat "$zigm_dest")" 'downloaded body'
}

test_wget_takes_a_timeout_for_a_body() {
    zigm_log="$ZIGM_TMP/wget-body"
    : >"$zigm_log"
    wget() {
        zigm_record "$zigm_log" "$@"
        printf 'body\n'
    }

    ZIGM_DOWNLOADER=wget
    ZIGM_CONNECT_TIMEOUT=7
    ZIGM_WGET_TRIES=0

    assert_out body fetch_stdout https://example.invalid/c
    assert_eq '-T 7 -O- -- https://example.invalid/c' \
        "$(cat "$zigm_log")" 'command line'
}

test_wget_takes_a_timeout_for_a_file() {
    zigm_log="$ZIGM_TMP/wget-file"
    zigm_dest="$ZIGM_TMP/wget-dest"
    : >"$zigm_log"
    wget() {
        zigm_record "$zigm_log" "$@"
        printf 'body\n' >"$zigm_dest"
    }

    ZIGM_DOWNLOADER=wget
    ZIGM_CONNECT_TIMEOUT=7
    ZIGM_WGET_TRIES=0

    assert_ok fetch_file https://example.invalid/d "$zigm_dest"
    assert_eq "-T 7 -O $zigm_dest -- https://example.invalid/d" \
        "$(cat "$zigm_log")" 'command line'
    assert_eq body "$(cat "$zigm_dest")" 'downloaded body'
}

# The retry loop here is the only one wanted, so a wget that retries on its own
# is told to try once.
test_wget_bounds_its_own_tries_when_it_takes_the_option() {
    zigm_log="$ZIGM_TMP/wget-tries"
    : >"$zigm_log"
    wget() {
        zigm_record "$zigm_log" "$@"
        printf 'body\n'
    }

    ZIGM_DOWNLOADER=wget
    ZIGM_CONNECT_TIMEOUT=7
    ZIGM_WGET_TRIES=1

    assert_out body fetch_stdout https://example.invalid/e
    assert_eq '-T 7 -t 1 -O- -- https://example.invalid/e' \
        "$(cat "$zigm_log")" 'command line'
}

test_wget_takes_tries_reads_the_help() {
    wget() {
        printf '  -t,  --tries=NUMBER   set number of retries to NUMBER\n'
    }
    assert_ok wget_takes_tries

    wget() {
        printf 'Usage: wget [-cqS] [-O FILE] [-T SEC] URL...\n'
    }
    assert_fails wget_takes_tries
}

test_an_unknown_downloader_fails() {
    ZIGM_DOWNLOADER=fetchit
    ZIGM_RETRIES=0
    ZIGM_RETRY_DELAY=0

    zigm_err="$ZIGM_TMP/unknown-err"
    fetch_stdout https://example.invalid/f >/dev/null 2>"$zigm_err"
    assert_ne 0 "$?" 'exit status'
    assert_contains "$(cat "$zigm_err")" 'unknown downloader' 'reason'
}

# ---------------------------------------------------------------------------
# Retries
# ---------------------------------------------------------------------------

test_a_download_that_works_is_made_once() {
    zigm_log="$ZIGM_TMP/once"
    : >"$zigm_log"
    curl() {
        zigm_record "$zigm_log" "$@"
        printf 'body\n'
    }

    ZIGM_DOWNLOADER=curl
    ZIGM_RETRIES=2
    ZIGM_RETRY_DELAY=0

    assert_out body fetch_stdout https://example.invalid/g
    assert_eq 1 "$(zigm_calls "$zigm_log")" 'attempts'
}

test_a_failed_download_is_tried_again() {
    zigm_log="$ZIGM_TMP/again"
    : >"$zigm_log"
    curl() {
        zigm_record "$zigm_log" "$@"
        if [ "$(zigm_calls "$zigm_log")" -lt 3 ]; then
            printf 'curl: (56) recv failure\n' >&2
            return 56
        fi
        printf 'body\n'
    }

    ZIGM_DOWNLOADER=curl
    ZIGM_RETRIES=2
    ZIGM_RETRY_DELAY=0

    assert_out body fetch_stdout https://example.invalid/h
    assert_eq 3 "$(zigm_calls "$zigm_log")" 'attempts'
}

test_retries_stop_at_the_configured_count() {
    zigm_log="$ZIGM_TMP/stop"
    : >"$zigm_log"
    curl() {
        zigm_record "$zigm_log" "$@"
        printf 'curl: (56) recv failure\n' >&2
        return 56
    }

    ZIGM_DOWNLOADER=curl
    ZIGM_RETRIES=2
    ZIGM_RETRY_DELAY=0

    assert_fails fetch_stdout https://example.invalid/i
    assert_eq 3 "$(zigm_calls "$zigm_log")" 'attempts'

    : >"$zigm_log"
    ZIGM_RETRIES=0
    assert_fails fetch_stdout https://example.invalid/i
    assert_eq 1 "$(zigm_calls "$zigm_log")" 'attempts without retries'
}

# A body cut off halfway must not reach the caller, and must not be mixed with
# the body the retry brings back.
test_a_partial_body_is_dropped() {
    zigm_log="$ZIGM_TMP/partial"
    : >"$zigm_log"
    curl() {
        zigm_record "$zigm_log" "$@"
        if [ "$(zigm_calls "$zigm_log")" -lt 2 ]; then
            printf '{"half of a doc'
            printf 'curl: (18) transfer closed\n' >&2
            return 18
        fi
        printf '{"whole": 1}\n'
    }

    ZIGM_DOWNLOADER=curl
    ZIGM_RETRIES=1
    ZIGM_RETRY_DELAY=0

    assert_out '{"whole": 1}' fetch_stdout https://example.invalid/j
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

test_a_failed_download_says_why() {
    zigm_err="$ZIGM_TMP/why"
    curl() {
        printf 'resolving example.invalid\n' >&2
        printf 'connecting to example.invalid\n' >&2
        printf 'curl: (22) The requested URL returned error: 404\n' >&2
        return 22
    }

    ZIGM_DOWNLOADER=curl
    ZIGM_RETRIES=0
    ZIGM_RETRY_DELAY=0
    ZIGM_VERBOSE=0

    fetch_stdout https://example.invalid/k >/dev/null 2>"$zigm_err"
    assert_ne 0 "$?" 'exit status'

    zigm_got=$(cat "$zigm_err")
    assert_contains "$zigm_got" 'error: 404' 'reason'
    assert_contains "$zigm_got" 'connecting to' 'the line before it'
    assert_not_contains "$zigm_got" 'resolving' 'the lines before those'
}

# wget puts the reason in the line before its last, so a one line report would
# say no more than 'Giving up.'.
test_a_failed_download_says_the_line_before_the_last_one() {
    zigm_err="$ZIGM_TMP/why-wget"
    wget() {
        printf 'Connecting to 10.0.0.1:80... failed: Connection timed out.\n' >&2
        printf 'Giving up.\n' >&2
        return 4
    }

    ZIGM_DOWNLOADER=wget
    ZIGM_WGET_TRIES=1
    ZIGM_RETRIES=0
    ZIGM_RETRY_DELAY=0
    ZIGM_VERBOSE=0

    fetch_stdout https://example.invalid/n >/dev/null 2>"$zigm_err"
    assert_ne 0 "$?" 'exit status'
    assert_contains "$(cat "$zigm_err")" 'Connection timed out' 'reason'
}

test_a_failed_download_says_all_of_it_when_verbose() {
    zigm_err="$ZIGM_TMP/why-v"
    curl() {
        printf 'resolving example.invalid\n' >&2
        printf 'connecting to example.invalid\n' >&2
        printf 'curl: (22) The requested URL returned error: 404\n' >&2
        return 22
    }

    ZIGM_DOWNLOADER=curl
    ZIGM_RETRIES=0
    ZIGM_RETRY_DELAY=0
    ZIGM_VERBOSE=1

    fetch_stdout https://example.invalid/l >/dev/null 2>"$zigm_err"
    assert_ne 0 "$?" 'exit status'

    zigm_got=$(cat "$zigm_err")
    assert_contains "$zigm_got" 'error: 404' 'reason'
    assert_contains "$zigm_got" 'resolving' 'the lines before it'
}

# What a downloader writes on its way to a good download is not a diagnostic,
# so a working download stays quiet, whichever of the two is in use.
test_a_download_that_works_stays_quiet() {
    zigm_err="$ZIGM_TMP/quiet"
    wget() {
        printf '\nsaving to: index.json\n100%%[=====>] 1.2M\n' >&2
        printf 'body\n'
    }

    ZIGM_DOWNLOADER=wget
    ZIGM_WGET_TRIES=1
    ZIGM_VERBOSE=0

    zigm_got=$(fetch_stdout https://example.invalid/m 2>"$zigm_err")
    assert_eq 0 "$?" 'exit status'
    assert_eq body "$zigm_got" 'body'
    assert_eq '' "$(cat "$zigm_err")" 'stderr'
}

run_tests
