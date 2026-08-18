#!/bin/sh
#
# Tests for version queries: the aliases, the partial versions, and the two
# wrappers that answer one against the installed versions and against the
# download index.
#
# Nothing here touches the network. The remote tests write an index fixture
# into a scratch cache directory and stamp it fresh, so require_index is a
# cache hit.

# The stub functions below are called by the code under test, never directly,
# and the globals set below are read by the sourced zigm, not by this file.
# shellcheck disable=SC2329,SC2034

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# The versions a list is answered against in the tests below: two lines of
# tagged releases, out of order, and a nightly.
zigm_versions='0.15.1
0.13.0
0.17.0-dev.1778+767d25269
0.14.1
0.15.0'

# A cut down download index, carrying master and three tagged releases, of
# which 0.13.0 has no build for x86_64 linux.
zigm_write_index() {
    cat >"$1" <<'EOF'
{
  "master": {
    "version": "0.17.0-dev.1778+767d25269",
    "x86_64-linux": {
      "tarball": "https://example.invalid/zig-master.tar.xz",
      "shasum": "1111"
    }
  },
  "0.15.1": {
    "version": "0.15.1",
    "x86_64-linux": {
      "tarball": "https://example.invalid/zig-0.15.1.tar.xz",
      "shasum": "2222"
    }
  },
  "0.15.0": {
    "version": "0.15.0",
    "x86_64-linux": {
      "tarball": "https://example.invalid/zig-0.15.0.tar.xz",
      "shasum": "3333"
    }
  },
  "0.13.0": {
    "aarch64-macos": {
      "tarball": "https://example.invalid/zig-0.13.0-macos.tar.xz",
      "shasum": "4444"
    }
  }
}
EOF
}

# Points the cache at scratch space and writes a fresh index fixture there.
zigm_cache_index() {
    ZIGM_CACHE_DIR="$ZIGM_TMP/cache"
    mkdir -p "$ZIGM_CACHE_DIR" || fail "cannot create $ZIGM_CACHE_DIR"
    zigm_write_index "$ZIGM_CACHE_DIR/index.json"
    date +%s >"$ZIGM_CACHE_DIR/index.json.stamp"
    ZIGM_REFRESH=0
    ZIGM_ARCH=x86_64
    ZIGM_OS=linux

    # Any download here would be a bug in the test or in the cache logic.
    fetch_file() { fail "fetch_file called for $1"; }
}

# Points the versions directory at scratch space and creates the versions
# named, as the directories find_versions reads.
zigm_fake_versions() {
    ZIGM_VERSIONS_DIR="$ZIGM_TMP/versions"
    rm -rf "$ZIGM_VERSIONS_DIR" || fail "cannot clear $ZIGM_VERSIONS_DIR"
    for zigm_fake_version in "$@"; do
        mkdir -p "$ZIGM_VERSIONS_DIR/$zigm_fake_version" ||
            fail "cannot create $zigm_fake_version"
    done
}

# ---------------------------------------------------------------------------
# Concrete versions
# ---------------------------------------------------------------------------

test_is_exact_version_accepts_a_full_version() {
    assert_ok is_exact_version 0.15.1
    assert_ok is_exact_version 1.0.0
    assert_ok is_exact_version 0.17.0-dev.1778+767d25269
    assert_ok is_exact_version master
}

test_is_exact_version_refuses_a_query() {
    assert_fails is_exact_version 0.15
    assert_fails is_exact_version 0
    assert_fails is_exact_version stable
    assert_fails is_exact_version latest
    assert_fails is_exact_version ''
    assert_fails is_exact_version 0.15.x
}

# ---------------------------------------------------------------------------
# Matching a query against a list
# ---------------------------------------------------------------------------

test_find_version_match_takes_an_exact_name_as_it_stands() {
    assert_out 0.15.1 find_version_match "$zigm_versions" 0.15.1
    assert_out 0.17.0-dev.1778+767d25269 \
        find_version_match "$zigm_versions" 0.17.0-dev.1778+767d25269
}

test_find_version_match_takes_the_newest_of_a_line() {
    assert_out 0.15.1 find_version_match "$zigm_versions" 0.15
    assert_out 0.13.0 find_version_match "$zigm_versions" 0.13
}

test_find_version_match_matches_whole_components_only() {
    assert_out 0.15.1 find_version_match '0.15.1
0.150.0' 0.15
    assert_fails find_version_match "$zigm_versions" 0.1
}

test_find_version_match_leaves_a_nightly_to_master() {
    # The newest thing in the list is a nightly, and neither a partial version
    # nor `stable` may answer with one.
    assert_out 0.15.1 find_version_match "$zigm_versions" 0
    assert_out 0.15.1 find_version_match "$zigm_versions" stable
    assert_fails find_version_match '0.17.0-dev.1778+767d25269' 0.17
}

test_find_version_match_reads_latest_as_master() {
    assert_out master find_version_match "$zigm_versions" latest
    assert_out master find_version_match '' latest
}

test_find_version_match_fails_on_a_query_nothing_answers() {
    assert_fails find_version_match "$zigm_versions" 0.99
    assert_fails find_version_match "$zigm_versions" nonsense
    assert_fails find_version_match "$zigm_versions" ''
    assert_fails find_version_match '' stable
}

# ---------------------------------------------------------------------------
# Against the installed versions
# ---------------------------------------------------------------------------

test_require_local_version_resolves_a_query() {
    zigm_fake_versions 0.14.1 0.15.0 0.15.1
    require_local_version 0.15
    assert_eq 0.15.1 "$ZIGM_WANTED_VERSION" 'resolved version'
    require_local_version stable
    assert_eq 0.15.1 "$ZIGM_WANTED_VERSION" 'resolved version'
}

test_require_local_version_passes_a_concrete_version_through() {
    # Nothing is installed, so a concrete version reaches the caller, which
    # reports a version that is not installed in its own words.
    zigm_fake_versions
    require_local_version 0.15.1
    assert_eq 0.15.1 "$ZIGM_WANTED_VERSION" 'resolved version'
    require_local_version master
    assert_eq master "$ZIGM_WANTED_VERSION" 'resolved version'
}

test_require_local_version_exits_on_a_query_nothing_answers() {
    zigm_fake_versions 0.14.1
    assert_status "$ZIGM_EX_ERROR" require_local_version 0.15
}

# ---------------------------------------------------------------------------
# Against the download index
# ---------------------------------------------------------------------------

test_require_remote_version_resolves_a_query() {
    zigm_cache_index
    require_remote_version 0.15
    assert_eq 0.15.1 "$ZIGM_WANTED_VERSION" 'resolved version'
    require_remote_version stable
    assert_eq 0.15.1 "$ZIGM_WANTED_VERSION" 'resolved version'
    require_remote_version latest
    assert_eq master "$ZIGM_WANTED_VERSION" 'resolved version'
}

test_require_remote_version_skips_a_version_without_a_build_here() {
    # The index carries 0.13.0 for macos alone, so nothing here answers it.
    zigm_cache_index
    assert_status "$ZIGM_EX_ERROR" require_remote_version 0.13
}

test_require_remote_version_reads_the_index_only_for_a_query() {
    # A concrete version needs no index, so the fetch below is never reached.
    ZIGM_CACHE_DIR="$ZIGM_TMP/empty-cache"
    fetch_file() { fail "fetch_file called for $1"; }
    require_remote_version 0.15.1
    assert_eq 0.15.1 "$ZIGM_WANTED_VERSION" 'resolved version'
    require_remote_version master
    assert_eq master "$ZIGM_WANTED_VERSION" 'resolved version'
}

# ---------------------------------------------------------------------------
# End to end
# ---------------------------------------------------------------------------

# Creates an installed version made of a stub zig, as install_fake does in
# tests/test_local.sh, in the data directory zigm_run points at.
zigm_install_fake() {
    zigm_install_fake_dir="$ZIGM_TMP/data/versions/$1"
    mkdir -p "$zigm_install_fake_dir" || fail "cannot create $1"
    printf '#!/bin/sh\n' >"$zigm_install_fake_dir/zig" || fail 'cannot write zig'
    chmod +x "$zigm_install_fake_dir/zig" || fail 'cannot make zig executable'
}

test_use_takes_a_partial_version() {
    rm -rf "$ZIGM_TMP/data"
    zigm_install_fake 0.15.0
    zigm_install_fake 0.15.1
    zigm_install_fake 0.14.1
    assert_status 0 zigm_run use 0.15
    assert_contains "$(zigm_run which)" '/versions/0.15.1/zig' 'active path'
}

test_use_takes_stable() {
    rm -rf "$ZIGM_TMP/data"
    zigm_install_fake 0.14.1
    zigm_install_fake 0.17.0-dev.1778+767d25269
    assert_status 0 zigm_run use stable
    assert_contains "$(zigm_run current)" 0.14.1 'active version'
}

test_use_reports_a_query_nothing_answers() {
    rm -rf "$ZIGM_TMP/data"
    zigm_install_fake 0.14.1
    assert_status "$ZIGM_EX_ERROR" zigm_run use 0.15
    assert_contains "$(zigm_run_out use 0.15)" 'no installed version matches' \
        'message'
}

test_uninstall_takes_a_partial_version() {
    rm -rf "$ZIGM_TMP/data"
    zigm_install_fake 0.15.0
    zigm_install_fake 0.15.1
    assert_status 0 zigm_run uninstall 0.15
    [ ! -d "$ZIGM_TMP/data/versions/0.15.1" ] || fail '0.15.1 is still there'
    assert_dir "$ZIGM_TMP/data/versions/0.15.0" '0.15.0 was removed too'
}

run_tests
