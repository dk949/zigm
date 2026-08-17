#!/bin/sh
#
# Tests for the commands that work on installed versions: use, uninstall,
# list, which, current, and clean. None of them touch the network, so the
# whole file runs offline, with fake installs made of stub executables.

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# reset_data
#
# Empties the scratch data directory zigm_run points at. The scratch space is
# shared by every test in the file, so a test that cares starts by clearing it.
reset_data() {
    rm -rf "$ZIGM_TMP/data" || fail "cannot clear $ZIGM_TMP/data"
}

# install_fake <version> [binary ...]
#
# Creates an installed version holding stub executables, zig and zls unless
# named otherwise, standing in for what install will eventually unpack.
install_fake() {
    install_fake_dir="$ZIGM_TMP/data/versions/$1"
    shift
    [ "$#" -gt 0 ] || set -- zig zls

    mkdir -p "$install_fake_dir" || fail "cannot create $install_fake_dir"
    for install_fake_bin in "$@"; do
        printf '#!/bin/sh\n' >"$install_fake_dir/$install_fake_bin" ||
            fail "cannot write $install_fake_bin"
        chmod +x "$install_fake_dir/$install_fake_bin" ||
            fail "cannot make $install_fake_bin executable"
    done
}

# ---------------------------------------------------------------------------
# Version names
# ---------------------------------------------------------------------------

test_is_version_name_accepts_what_upstream_produces() {
    assert_ok is_version_name 0.15.1
    assert_ok is_version_name '0.16.0-dev.123+abc123'
    assert_ok is_version_name master
}

test_is_version_name_rejects_anything_reaching_outside() {
    assert_fails is_version_name ''
    assert_fails is_version_name .
    assert_fails is_version_name ..
    assert_fails is_version_name ../0.15.1
    assert_fails is_version_name 0.15.1/bin
    assert_fails is_version_name /0.15.1
    assert_fails is_version_name .partial
}

# ---------------------------------------------------------------------------
# Listing and sorting
# ---------------------------------------------------------------------------

test_find_versions_lists_directories_only() {
    zigm_dir="$ZIGM_TMP/find/versions"
    mkdir -p "$zigm_dir/0.15.1" "$zigm_dir/.partial"
    : >"$zigm_dir/a-file"
    assert_out '0.15.1' find_versions "$zigm_dir"
}

test_find_versions_is_empty_when_nothing_is_installed() {
    zigm_dir="$ZIGM_TMP/empty/versions"
    mkdir -p "$zigm_dir"
    assert_out '' find_versions "$zigm_dir"
}

test_find_versions_fails_without_a_versions_directory() {
    assert_fails find_versions "$ZIGM_TMP/nowhere"
}

test_sort_versions_orders_numerically() {
    zigm_out=$(printf '%s\n' 0.10.0 0.9.0 0.15.1 1.0.0 | sort_versions)
    assert_eq '0.9.0
0.10.0
0.15.1
1.0.0' "$zigm_out" 'sorted versions'
}

test_sort_versions_puts_a_dev_build_before_its_release() {
    zigm_out=$(printf '%s\n' 0.16.0 '0.16.0-dev.123+abc' '0.16.0-dev.45+xy' |
        sort_versions)
    assert_eq '0.16.0-dev.45+xy
0.16.0-dev.123+abc
0.16.0' "$zigm_out" 'sorted versions'
}

# ---------------------------------------------------------------------------
# The current link
# ---------------------------------------------------------------------------

test_find_link_version_names_the_target() {
    zigm_root="$ZIGM_TMP/link"
    mkdir -p "$zigm_root/versions/0.15.1"
    ln -s "$zigm_root/versions/0.15.1" "$zigm_root/current"
    assert_out '0.15.1' find_link_version "$zigm_root/current"
}

test_find_link_version_fails_on_a_missing_or_broken_link() {
    zigm_root="$ZIGM_TMP/broken"
    mkdir -p "$zigm_root"
    assert_fails find_link_version "$zigm_root/current"

    ln -s "$zigm_root/versions/0.15.1" "$zigm_root/current"
    assert_fails find_link_version "$zigm_root/current"
}

test_find_link_version_fails_on_a_plain_directory() {
    zigm_root="$ZIGM_TMP/plain"
    mkdir -p "$zigm_root/current"
    assert_fails find_link_version "$zigm_root/current"
}

test_swap_link_creates_and_replaces_the_link() {
    zigm_root="$ZIGM_TMP/swap"
    mkdir -p "$zigm_root/versions/0.15.1" "$zigm_root/versions/0.14.1"

    assert_ok swap_link "$zigm_root/versions/0.15.1" "$zigm_root/current"
    assert_out '0.15.1' find_link_version "$zigm_root/current"

    assert_ok swap_link "$zigm_root/versions/0.14.1" "$zigm_root/current"
    assert_out '0.14.1' find_link_version "$zigm_root/current"
}

test_swap_link_works_without_a_mv_that_takes_an_option() {
    # busybox mv has neither -T nor -h, so the unlink and rename fallback is
    # what runs there. A stub standing in for it keeps that path covered
    # everywhere.
    # shellcheck disable=SC2329 # swap_link calls it.
    mv() {
        case "$1" in
            -T | -h) return 1 ;;
        esac
        command mv "$@"
    }

    zigm_root="$ZIGM_TMP/swap_fallback"
    mkdir -p "$zigm_root/versions/0.15.1" "$zigm_root/versions/0.14.1"

    assert_ok swap_link "$zigm_root/versions/0.15.1" "$zigm_root/current"
    assert_ok swap_link "$zigm_root/versions/0.14.1" "$zigm_root/current"
    assert_out '0.14.1' find_link_version "$zigm_root/current"
}

test_swap_link_leaves_no_scratch_link_behind() {
    zigm_root="$ZIGM_TMP/swap_clean"
    mkdir -p "$zigm_root/versions/0.15.1"
    assert_ok swap_link "$zigm_root/versions/0.15.1" "$zigm_root/current"
    [ ! -e "$zigm_root/current.new" ] && [ ! -L "$zigm_root/current.new" ] ||
        fail 'the scratch link was left behind'
}

test_swap_link_fails_on_a_target_that_is_not_there() {
    zigm_root="$ZIGM_TMP/swap_missing"
    mkdir -p "$zigm_root"
    assert_fails swap_link "$zigm_root/versions/0.15.1" "$zigm_root/current"
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

test_list_reports_an_empty_data_directory_on_stderr() {
    reset_data
    assert_out '' zigm_run list
    assert_contains "$(zigm_run_out list)" 'no versions installed' 'note'
    assert_status 0 zigm_run list
}

test_list_marks_the_active_version() {
    reset_data
    install_fake 0.14.1
    install_fake 0.15.1
    zigm_run use 0.15.1 >/dev/null 2>&1

    assert_out '  0.14.1
* 0.15.1' zigm_run list
}

test_list_orders_oldest_first() {
    reset_data
    install_fake 0.15.1
    install_fake 0.9.0
    install_fake '0.16.0-dev.99+ab'

    assert_out '  0.9.0
  0.15.1
  0.16.0-dev.99+ab' zigm_run list
}

# ---------------------------------------------------------------------------
# use and current
# ---------------------------------------------------------------------------

test_use_activates_an_installed_version() {
    reset_data
    install_fake 0.15.1
    assert_status 0 zigm_run use 0.15.1
    assert_out '0.15.1' zigm_run current
}

test_use_switches_between_versions() {
    reset_data
    install_fake 0.14.1
    install_fake 0.15.1
    zigm_run use 0.14.1 >/dev/null 2>&1
    assert_status 0 zigm_run use 0.15.1
    assert_out '0.15.1' zigm_run current
}

test_use_rejects_a_version_that_is_not_installed() {
    reset_data
    assert_status "$ZIGM_EX_ERROR" zigm_run use 0.15.1
    assert_contains "$(zigm_run_out use 0.15.1)" 'is not installed' 'message'
}

test_use_explains_that_master_is_stored_under_its_version() {
    reset_data
    assert_status "$ZIGM_EX_ERROR" zigm_run use master
    assert_contains "$(zigm_run_out use master)" 'resolved version' 'message'
}

test_use_rejects_a_version_reaching_out_of_the_versions_directory() {
    reset_data
    assert_status "$ZIGM_EX_USAGE" zigm_run use ../elsewhere
}

test_current_fails_when_no_version_is_active() {
    reset_data
    install_fake 0.15.1
    assert_status "$ZIGM_EX_ERROR" zigm_run current
    assert_contains "$(zigm_run_out current)" 'no version is active' 'message'
}

# ---------------------------------------------------------------------------
# which
# ---------------------------------------------------------------------------

test_which_defaults_to_zig() {
    reset_data
    install_fake 0.15.1
    zigm_run use 0.15.1 >/dev/null 2>&1
    assert_out "$ZIGM_TMP/data/versions/0.15.1/zig" zigm_run which
}

test_which_takes_a_binary_name() {
    reset_data
    install_fake 0.15.1
    zigm_run use 0.15.1 >/dev/null 2>&1
    assert_out "$ZIGM_TMP/data/versions/0.15.1/zls" zigm_run which zls
}

test_which_fails_on_a_binary_the_version_does_not_have() {
    reset_data
    install_fake 0.15.1 zig
    zigm_run use 0.15.1 >/dev/null 2>&1
    assert_status "$ZIGM_EX_ERROR" zigm_run which zls
}

test_which_fails_when_no_version_is_active() {
    reset_data
    install_fake 0.15.1
    assert_status "$ZIGM_EX_ERROR" zigm_run which
}

test_which_rejects_a_name_reaching_out_of_the_version() {
    reset_data
    install_fake 0.15.1
    zigm_run use 0.15.1 >/dev/null 2>&1
    assert_status "$ZIGM_EX_USAGE" zigm_run which ../../zig
}

# ---------------------------------------------------------------------------
# uninstall
# ---------------------------------------------------------------------------

test_uninstall_removes_the_version() {
    reset_data
    install_fake 0.14.1
    install_fake 0.15.1
    assert_status 0 zigm_run uninstall 0.14.1
    [ ! -d "$ZIGM_TMP/data/versions/0.14.1" ] || fail 'the version is still there'
    assert_out '  0.15.1' zigm_run list
}

test_uninstall_drops_the_link_when_the_version_is_active() {
    reset_data
    install_fake 0.15.1
    zigm_run use 0.15.1 >/dev/null 2>&1

    zigm_out=$(zigm_run_out uninstall 0.15.1)
    assert_contains "$zigm_out" 'was active' 'warning'
    [ ! -L "$ZIGM_TMP/data/current" ] || fail 'the link is still there'
    assert_status "$ZIGM_EX_ERROR" zigm_run current
}

test_uninstall_keeps_the_link_when_another_version_is_active() {
    reset_data
    install_fake 0.14.1
    install_fake 0.15.1
    zigm_run use 0.15.1 >/dev/null 2>&1
    assert_status 0 zigm_run uninstall 0.14.1
    assert_out '0.15.1' zigm_run current
}

test_uninstall_rejects_a_version_that_is_not_installed() {
    reset_data
    assert_status "$ZIGM_EX_ERROR" zigm_run uninstall 0.15.1
}

test_uninstall_rejects_a_version_reaching_out_of_the_versions_directory() {
    reset_data
    assert_status "$ZIGM_EX_USAGE" zigm_run uninstall ../elsewhere
}

# ---------------------------------------------------------------------------
# Recursive removals
# ---------------------------------------------------------------------------

test_is_removable_refuses_the_root_directory() {
    assert_fails is_removable /
    assert_fails is_removable //
    assert_fails is_removable /.
    assert_fails is_removable /..
}

test_is_removable_refuses_a_link_to_the_root() {
    rm -f "$ZIGM_TMP/root-link"
    ln -s / "$ZIGM_TMP/root-link"
    assert_fails is_removable "$ZIGM_TMP/root-link"
}

test_is_removable_refuses_what_is_not_there() {
    assert_fails is_removable "$ZIGM_TMP/nowhere"
    assert_fails is_removable ''
}

test_is_removable_accepts_a_directory_below_the_root() {
    mkdir -p "$ZIGM_TMP/removable"
    assert_ok is_removable "$ZIGM_TMP/removable"
    assert_ok is_removable "$ZIGM_TMP/removable/."
}

# ---------------------------------------------------------------------------
# clean
# ---------------------------------------------------------------------------

test_clean_refuses_a_cache_directory_of_root() {
    # `rm` is replaced rather than trusted, so a regression here fails the test
    # instead of the machine. It records the call, since a stub that failed the
    # test would exit 1 and read as the error the assertion is looking for.
    # shellcheck disable=SC2329 # cmd_clean calls it, if it is broken.
    rm() { printf '%s\n' "$*" >>"$ZIGM_TMP/rm-calls"; }

    # shellcheck disable=SC2034 # cmd_clean reads it.
    ZIGM_CACHE_DIR=/
    assert_status "$ZIGM_EX_ERROR" cmd_clean
    assert_contains "$(cmd_clean 2>&1)" 'refusing to remove' 'message'

    [ ! -f "$ZIGM_TMP/rm-calls" ] ||
        fail "rm was called: $(cat "$ZIGM_TMP/rm-calls")"
}

test_clean_removes_the_cache_directory() {
    mkdir -p "$ZIGM_TMP/cache"
    : >"$ZIGM_TMP/cache/index.json"
    assert_status 0 zigm_run clean
    [ ! -d "$ZIGM_TMP/cache" ] || fail 'the cache is still there'
}

test_clean_is_repeatable() {
    rm -rf "$ZIGM_TMP/cache"
    assert_status 0 zigm_run clean
    assert_contains "$(zigm_run_out clean)" 'already empty' 'note'
}

test_clean_leaves_installed_versions_alone() {
    reset_data
    install_fake 0.15.1
    mkdir -p "$ZIGM_TMP/cache"
    assert_status 0 zigm_run clean
    assert_dir "$ZIGM_TMP/data/versions/0.15.1" 'installed version'
}

test_clean_sweeps_what_an_unfinished_install_left() {
    reset_data
    install_fake 0.15.1
    mkdir -p "$ZIGM_TMP/data/versions/.new-0.16.0/root"

    assert_contains "$(zigm_run_out clean)" 'unfinished install of zig 0.16.0' \
        'sweep report'
    [ ! -e "$ZIGM_TMP/data/versions/.new-0.16.0" ] ||
        fail 'the scratch directory is still there'
    assert_dir "$ZIGM_TMP/data/versions/0.15.1" 'installed version'
}

test_clean_puts_back_a_version_an_unfinished_reinstall_moved_aside() {
    reset_data
    install_fake 0.15.1
    mv "$ZIGM_TMP/data/versions/0.15.1" "$ZIGM_TMP/data/versions/.old-0.15.1"

    assert_status 0 zigm_run clean
    assert_file "$ZIGM_TMP/data/versions/0.15.1/zig" 'the restored version'
    [ ! -e "$ZIGM_TMP/data/versions/.old-0.15.1" ] ||
        fail 'the moved aside copy is still there'
}

test_clean_sweeps_even_when_the_cache_is_already_empty() {
    reset_data
    rm -rf "$ZIGM_TMP/cache"
    mkdir -p "$ZIGM_TMP/data/versions/.new-0.16.0"

    assert_status 0 zigm_run clean
    [ ! -e "$ZIGM_TMP/data/versions/.new-0.16.0" ] ||
        fail 'the scratch directory survived an empty cache'
}

run_tests
