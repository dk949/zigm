#!/bin/sh
#
# Tests for the record of the version an activation replaced, which `zigm use -`
# goes back to. Nothing here installs anything: a version is an empty directory
# and an activation is a symlink swap.

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# make_data <name> <version ...>
#
# Creates a scratch data directory of its own, holding a version directory for
# each name given, and sets zigm_root, zigm_link, and zigm_record to the paths
# the tests below work with.
make_data() {
    zigm_root="$ZIGM_TMP/$1"
    shift

    rm -rf "$zigm_root" || fail "cannot clear $zigm_root"
    for zigm_version in "$@"; do
        mkdir -p "$zigm_root/versions/$zigm_version" ||
            fail "cannot create $zigm_version"
    done
    mkdir -p "$zigm_root/state" || fail "cannot create the state directory"

    zigm_link="$zigm_root/current"
    zigm_record="$zigm_root/state/previous"
}

# ---------------------------------------------------------------------------
# Reading the record
# ---------------------------------------------------------------------------

test_find_previous_reads_the_record() {
    make_data read 0.15.1
    printf '0.15.1\n' >"$zigm_record"
    assert_out '0.15.1' find_previous "$zigm_record"
}

test_find_previous_fails_without_a_record() {
    make_data missing
    assert_fails find_previous "$zigm_record"
}

test_find_previous_fails_on_an_empty_record() {
    make_data empty
    : >"$zigm_record"
    assert_fails find_previous "$zigm_record"
}

test_find_previous_refuses_a_record_reaching_outside() {
    make_data outside
    printf '../elsewhere\n' >"$zigm_record"
    assert_fails find_previous "$zigm_record"
}

test_find_previous_reads_the_first_line_alone() {
    make_data lines
    printf '0.15.1\n0.14.1\n' >"$zigm_record"
    assert_out '0.15.1' find_previous "$zigm_record"
}

# ---------------------------------------------------------------------------
# Writing the record
# ---------------------------------------------------------------------------

test_write_previous_records_a_version() {
    make_data write
    write_previous "$zigm_record" 0.15.1
    assert_out '0.15.1' find_previous "$zigm_record"
}

test_write_previous_replaces_an_older_record() {
    make_data replace
    write_previous "$zigm_record" 0.14.1
    write_previous "$zigm_record" 0.15.1
    assert_out '0.15.1' find_previous "$zigm_record"
}

test_write_previous_warns_rather_than_failing() {
    make_data unwritable
    zigm_out=$(write_previous "$zigm_root/nowhere/previous" 0.15.1 2>&1)
    zigm_status=$?
    assert_eq 0 "$zigm_status" 'status'
    assert_contains "$zigm_out" 'cannot record the previous version' 'warning'
}

# ---------------------------------------------------------------------------
# Activating
# ---------------------------------------------------------------------------

test_activate_version_points_the_link_at_the_version() {
    make_data point 0.15.1
    assert_ok activate_version "$zigm_root/versions/0.15.1" "$zigm_link" \
        "$zigm_record"
    assert_out '0.15.1' find_link_version "$zigm_link"
}

test_activate_version_records_what_it_replaced() {
    make_data records 0.14.1 0.15.1
    activate_version "$zigm_root/versions/0.14.1" "$zigm_link" "$zigm_record"
    activate_version "$zigm_root/versions/0.15.1" "$zigm_link" "$zigm_record"
    assert_out '0.14.1' find_previous "$zigm_record"
}

test_activate_version_records_nothing_on_a_first_activation() {
    make_data first 0.15.1
    activate_version "$zigm_root/versions/0.15.1" "$zigm_link" "$zigm_record"
    assert_fails find_previous "$zigm_record"
}

test_activate_version_leaves_the_record_when_nothing_changes() {
    make_data unchanged 0.14.1 0.15.1
    activate_version "$zigm_root/versions/0.14.1" "$zigm_link" "$zigm_record"
    activate_version "$zigm_root/versions/0.15.1" "$zigm_link" "$zigm_record"
    activate_version "$zigm_root/versions/0.15.1" "$zigm_link" "$zigm_record"
    assert_out '0.14.1' find_previous "$zigm_record"
}

test_activate_version_writes_no_record_when_the_swap_fails() {
    make_data failed 0.14.1 0.15.1
    activate_version "$zigm_root/versions/0.14.1" "$zigm_link" "$zigm_record"
    assert_fails activate_version "$zigm_root/versions/0.15.1" \
        "$zigm_root/nowhere/current" "$zigm_record"
    assert_fails find_previous "$zigm_record"
}

run_tests
