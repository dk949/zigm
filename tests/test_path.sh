#!/bin/sh
#
# Tests for the PATH check made after an activation. Nothing here touches the
# network: the path lists are scratch directories holding stub executables,
# and the end to end tests activate a fake install.

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# make_dir <path>
#
# Creates a directory and prints it, so a test can name one in the same line
# it makes it in.
make_dir() {
    mkdir -p "$1" || fail "cannot create $1"
    printf '%s\n' "$1"
}

# make_zig <directory>
#
# Puts a zig stub in a directory, creating it first.
make_zig() {
    make_dir "$1" >/dev/null
    printf '#!/bin/sh\n' >"$1/zig" || fail "cannot write $1/zig"
    chmod +x "$1/zig" || fail "cannot make $1/zig executable"
}

# install_fake <version>
#
# Creates an installed version holding a zig stub, standing in for what an
# install unpacks.
install_fake() {
    make_zig "$ZIGM_TMP/data/versions/$1"
}

# reset_data
reset_data() {
    rm -rf "$ZIGM_TMP/data" || fail "cannot clear $ZIGM_TMP/data"
}

# ---------------------------------------------------------------------------
# find_real_dir
# ---------------------------------------------------------------------------

test_real_dir_resolves_symlinks() {
    zigm_root=$(make_dir "$ZIGM_TMP/real/target")
    ln -sfn "$zigm_root" "$ZIGM_TMP/real/link" || fail 'cannot link'

    assert_out "$(find_real_dir "$zigm_root")" find_real_dir "$ZIGM_TMP/real/link"
    assert_out "$(find_real_dir "$zigm_root")" find_real_dir "$zigm_root/"
}

test_real_dir_refuses_the_unreachable() {
    assert_fails find_real_dir ''
    assert_fails find_real_dir "$ZIGM_TMP/real/nowhere"
}

# ---------------------------------------------------------------------------
# is_on_path
# ---------------------------------------------------------------------------

test_on_path_finds_the_directory() {
    zigm_dir=$(make_dir "$ZIGM_TMP/onpath/bin")

    assert_ok is_on_path "$zigm_dir" "$zigm_dir"
    assert_ok is_on_path "$zigm_dir" "/nowhere:$zigm_dir:/elsewhere"
}

test_on_path_compares_physical_paths() {
    zigm_dir=$(make_dir "$ZIGM_TMP/physical/bin")
    ln -sfn "$zigm_dir" "$ZIGM_TMP/physical/link" || fail 'cannot link'

    # A trailing slash, a detour through `..`, and a symlink to the same place
    # all name the directory that is on the list.
    assert_ok is_on_path "$zigm_dir/" "$zigm_dir"
    assert_ok is_on_path "$zigm_dir" "$ZIGM_TMP/physical/bin/../bin"
    assert_ok is_on_path "$ZIGM_TMP/physical/link" "$zigm_dir"
}

test_on_path_misses_what_is_absent() {
    zigm_dir=$(make_dir "$ZIGM_TMP/absent/bin")
    zigm_other=$(make_dir "$ZIGM_TMP/absent/other")

    assert_fails is_on_path "$zigm_dir" "$zigm_other"
    assert_fails is_on_path "$zigm_dir" ''
    # A directory that is not there is on no path list at all.
    assert_fails is_on_path "$ZIGM_TMP/absent/gone" "$ZIGM_TMP/absent/gone"
}

test_on_path_leaves_an_entry_unexpanded() {
    zigm_dir=$(make_dir "$ZIGM_TMP/glob/bin")
    make_dir "$ZIGM_TMP/glob/star" >/dev/null

    # An entry is a path rather than a pattern, so a `*` in one matches
    # nothing but itself.
    assert_fails is_on_path "$zigm_dir" "$ZIGM_TMP/glob/*"
}

# ---------------------------------------------------------------------------
# find_zig_dir
# ---------------------------------------------------------------------------

test_zig_dir_takes_the_first() {
    zigm_first=$ZIGM_TMP/first/a
    zigm_second=$ZIGM_TMP/first/b
    make_zig "$zigm_first"
    make_zig "$zigm_second"

    assert_out "$(find_real_dir "$zigm_first")" \
        find_zig_dir "$zigm_first:$zigm_second"
    assert_out "$(find_real_dir "$zigm_second")" \
        find_zig_dir "$zigm_second:$zigm_first"
}

test_zig_dir_skips_what_cannot_run() {
    zigm_dir=$(make_dir "$ZIGM_TMP/skip/plain")
    printf '#!/bin/sh\n' >"$zigm_dir/zig" || fail 'cannot write zig'
    make_dir "$ZIGM_TMP/skip/dir/zig" >/dev/null
    make_zig "$ZIGM_TMP/skip/real"

    # A zig that is not executable, and a directory named zig, are both passed
    # over for the one that can actually run.
    assert_out "$(find_real_dir "$ZIGM_TMP/skip/real")" \
        find_zig_dir "$zigm_dir:$ZIGM_TMP/skip/dir:$ZIGM_TMP/skip/real"
}

test_zig_dir_fails_without_a_zig() {
    zigm_dir=$(make_dir "$ZIGM_TMP/none/bin")

    assert_fails find_zig_dir "$zigm_dir"
    assert_fails find_zig_dir ''
}

# ---------------------------------------------------------------------------
# warn_path
# ---------------------------------------------------------------------------

test_warn_path_reports_a_missing_directory() {
    make_zig "$ZIGM_TMP/warn/versions/0.15.1"
    ln -sfn "$ZIGM_TMP/warn/versions/0.15.1" "$ZIGM_TMP/warn/current" ||
        fail 'cannot link'
    zigm_elsewhere=$(make_dir "$ZIGM_TMP/warn/elsewhere")

    # The real path list stays on the end, since a shell whose printf is an
    # external command needs it to say anything at all.
    # shellcheck disable=SC2030,SC2031 # each test runs in a subshell of its own.
    zigm_out=$(PATH="$zigm_elsewhere:$PATH" warn_path "$ZIGM_TMP/warn/current" 2>&1)
    assert_contains "$zigm_out" 'is not on PATH' 'message'
    assert_contains "$zigm_out" 'PATH="' 'hint'
}

test_warn_path_is_quiet_when_the_link_leads() {
    make_zig "$ZIGM_TMP/lead/versions/0.15.1"
    ln -sfn "$ZIGM_TMP/lead/versions/0.15.1" "$ZIGM_TMP/lead/current" ||
        fail 'cannot link'
    make_zig "$ZIGM_TMP/lead/other"

    # shellcheck disable=SC2030,SC2031 # each test runs in a subshell of its own.
    zigm_out=$(
        PATH="$ZIGM_TMP/lead/current:$ZIGM_TMP/lead/other:$PATH"
        warn_path "$ZIGM_TMP/lead/current" 2>&1
    )
    assert_eq '' "$zigm_out" 'output'
}

test_warn_path_reports_a_zig_ahead_of_the_link() {
    make_zig "$ZIGM_TMP/ahead/versions/0.15.1"
    ln -sfn "$ZIGM_TMP/ahead/versions/0.15.1" "$ZIGM_TMP/ahead/current" ||
        fail 'cannot link'
    make_zig "$ZIGM_TMP/ahead/system"

    # shellcheck disable=SC2030,SC2031 # each test runs in a subshell of its own.
    zigm_out=$(
        PATH="$ZIGM_TMP/ahead/system:$ZIGM_TMP/ahead/current:$PATH"
        warn_path "$ZIGM_TMP/ahead/current" 2>&1
    )
    assert_contains "$zigm_out" 'comes before' 'message'
    assert_contains "$zigm_out" "$ZIGM_TMP/ahead/system/zig" 'the zig found'
}

test_warn_path_keeps_the_warning_under_quiet() {
    make_zig "$ZIGM_TMP/quiet/versions/0.15.1"
    ln -sfn "$ZIGM_TMP/quiet/versions/0.15.1" "$ZIGM_TMP/quiet/current" ||
        fail 'cannot link'

    zigm_elsewhere=$(make_dir "$ZIGM_TMP/quiet/elsewhere")
    zigm_out=$(
        # shellcheck disable=SC2034 # the sourced note reads it.
        ZIGM_QUIET=1
        # shellcheck disable=SC2030,SC2031 # the subshell keeps it local.
        PATH="$zigm_elsewhere:$PATH"
        warn_path "$ZIGM_TMP/quiet/current" 2>&1
    )
    # The warning stands, while the hint below it is an aside and goes.
    assert_contains "$zigm_out" 'is not on PATH' 'message'
    assert_not_contains "$zigm_out" 'put it there' 'hint'
}

# ---------------------------------------------------------------------------
# End to end
# ---------------------------------------------------------------------------

test_use_warns_when_the_link_is_not_on_path() {
    reset_data
    install_fake 0.15.1

    zigm_out=$(zigm_run_out use 0.15.1)
    assert_contains "$zigm_out" 'now using zig 0.15.1' 'activation'
    assert_contains "$zigm_out" "$ZIGM_TMP/data/current is not on PATH" 'warning'
}

test_use_is_quiet_when_the_link_is_on_path() {
    reset_data
    install_fake 0.15.1

    # shellcheck disable=SC2030,SC2031 # each test runs in a subshell of its own.
    zigm_out=$(PATH="$ZIGM_TMP/data/current:$PATH" zigm_run_out use 0.15.1)
    assert_not_contains "$zigm_out" 'PATH' 'warning'
}

run_tests
