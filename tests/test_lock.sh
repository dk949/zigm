#!/bin/sh
#
# Tests for the lock the writing commands take over the data directory.
#
# Nothing here touches the network: the commands used are the ones that work on
# local state alone, since what is under test is who gets to run at all rather
# than what they do.

# The globals set below are read by the sourced zigm, not by this file.
# shellcheck disable=SC2034

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# The lock zigm_run takes, since it points the data directory at scratch space.
zigm_lock="$ZIGM_TMP/data/.lock"

# hold_lock [pid]
#
# Takes the lock the way zigm does, recording the pid given or none at all.
hold_lock() {
    rm -rf "$zigm_lock" || fail "cannot clear $zigm_lock"
    mkdir -p "$zigm_lock" || fail "cannot create $zigm_lock"
    [ "$#" -eq 0 ] || printf '%s\n' "$1" >"$zigm_lock/pid"
}

# Prints a pid that is certainly not running: a background shell that has been
# waited for. The number could in principle be handed out again, but not in the
# moment between the wait and the check.
dead_pid() {
    (exit 0) &
    dead_pid_value=$!
    wait "$dead_pid_value" 2>/dev/null
    printf '%s\n' "$dead_pid_value"
}

# Empties the scratch data directory, lock and all.
reset_data() {
    rm -rf "$ZIGM_TMP/data" || fail "cannot clear $ZIGM_TMP/data"
}

# ---------------------------------------------------------------------------
# Reading a lock
# ---------------------------------------------------------------------------

test_find_lock_pid_reads_the_recorded_pid() {
    hold_lock 4242
    assert_out 4242 find_lock_pid "$zigm_lock"
}

test_find_lock_pid_fails_without_a_pid_file() {
    hold_lock
    assert_fails find_lock_pid "$zigm_lock"
}

test_find_lock_pid_refuses_something_that_is_not_a_pid() {
    hold_lock
    printf 'not a pid\n' >"$zigm_lock/pid"
    assert_fails find_lock_pid "$zigm_lock"
}

test_is_stale_lock_is_false_for_a_live_owner() {
    # The test shell itself, which is as live as an owner gets.
    hold_lock "$$"
    assert_fails is_stale_lock "$zigm_lock"
}

test_is_stale_lock_is_true_for_a_dead_owner() {
    hold_lock "$(dead_pid)"
    assert_ok is_stale_lock "$zigm_lock"
}

test_is_stale_lock_is_false_without_a_pid_file() {
    # A run that has not written its pid yet cannot be told from one that died
    # before it could, so neither is reclaimed.
    hold_lock
    assert_fails is_stale_lock "$zigm_lock"
}

# ---------------------------------------------------------------------------
# Taking the lock
# ---------------------------------------------------------------------------

test_a_held_lock_stops_a_writing_command() {
    reset_data
    hold_lock "$$"
    assert_status "$ZIGM_EX_ERROR" zigm_run clean
    assert_contains "$(zigm_run_out clean)" 'another zigm is running' 'message'
    assert_dir "$zigm_lock" 'the lock survived'
}

test_a_held_lock_stops_every_writing_command() {
    reset_data
    hold_lock "$$"
    assert_status "$ZIGM_EX_ERROR" zigm_run use 0.15.1
    assert_status "$ZIGM_EX_ERROR" zigm_run uninstall 0.15.1
    assert_status "$ZIGM_EX_ERROR" zigm_run install 0.15.1
    assert_status "$ZIGM_EX_ERROR" zigm_run update
}

test_a_held_lock_leaves_the_reading_commands_alone() {
    reset_data
    hold_lock "$$"
    assert_status 0 zigm_run list
    assert_status 0 zigm_run list-remote --help
    assert_dir "$zigm_lock" 'a reading command took the lock'
}

test_a_lock_without_a_pid_is_not_reclaimed() {
    reset_data
    hold_lock
    assert_status "$ZIGM_EX_ERROR" zigm_run clean
    assert_contains "$(zigm_run_out clean)" 'stale lock' 'message'
}

test_a_lock_whose_owner_is_gone_is_reclaimed() {
    reset_data
    hold_lock "$(dead_pid)"
    zigm_out=$(zigm_run_out clean)
    assert_contains "$zigm_out" 'reclaiming the lock' 'warning'
    [ ! -e "$zigm_lock" ] || fail 'the reclaimed lock was not given back'

    # And the command it let through really ran.
    hold_lock "$(dead_pid)"
    assert_status 0 zigm_run clean
}

# ---------------------------------------------------------------------------
# Giving it back
# ---------------------------------------------------------------------------

test_the_lock_is_gone_after_a_command_succeeds() {
    reset_data
    assert_status 0 zigm_run clean
    [ ! -e "$zigm_lock" ] || fail 'the lock outlived the command'
}

test_the_lock_is_gone_after_a_command_fails() {
    reset_data
    assert_status "$ZIGM_EX_ERROR" zigm_run uninstall 0.15.1
    [ ! -e "$zigm_lock" ] || fail 'the lock outlived the command'
}

test_the_lock_is_gone_after_a_usage_error() {
    reset_data
    assert_status "$ZIGM_EX_USAGE" zigm_run uninstall
    [ ! -e "$zigm_lock" ] || fail 'the lock outlived the command'
}

test_one_command_follows_another() {
    reset_data
    assert_status 0 zigm_run clean
    assert_status 0 zigm_run clean
}

# require_lock is called here rather than through a command, since the pid it
# records is only there while the run holding the lock is still going.
test_require_lock_records_this_run() {
    reset_data
    ZIGM_DATA_DIR="$ZIGM_TMP/data"
    ZIGM_LOCK_DIR=''

    require_lock
    assert_out "$$" find_lock_pid "$zigm_lock"

    drop_lock
    [ ! -e "$zigm_lock" ] || fail 'drop_lock left the lock behind'
}

test_require_lock_is_reentrant() {
    reset_data
    ZIGM_DATA_DIR="$ZIGM_TMP/data"
    ZIGM_LOCK_DIR=''

    require_lock
    # A second command in one run would otherwise report the run against
    # itself, since the lock is given back on the way out and not before.
    assert_ok require_lock

    drop_lock
}

run_tests
